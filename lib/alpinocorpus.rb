require 'ffi'

module EntriesIterate
  def entriesIterate(iter)
    begin
      # Retrieve iterate value as a pointer, we have to free it.
      strPtr = AlpinoCorpus::alpinocorpus_iter_value(iter)

      # Convert and yield the string.
      str = strPtr.get_string(0)
      yield str

      # Free the C string.
      AlpinoCorpusLibC::free(strPtr)
    end while AlpinoCorpus::alpinocorpus_iter_next(@reader, iter) != 0

    AlpinoCorpus::alpinocorpus_iter_destroy(iter)
  end
end


module AlpinoCorpus
  extend FFI::Library

  ffi_lib 'alpino_corpus'

  attach_function :alpinocorpus_open, [:string], :pointer
  attach_function :alpinocorpus_close, [:pointer], :void
  attach_function :alpinocorpus_read, [:pointer, :string], :pointer
  attach_function :alpinocorpus_entry_iter, [:pointer], :pointer
  attach_function :alpinocorpus_query_iter, [:pointer, :string], :pointer
  attach_function :alpinocorpus_iter_next, [:pointer, :pointer], :int
  attach_function :alpinocorpus_iter_value, [:pointer], :pointer
  attach_function :alpinocorpus_iter_destroy, [:pointer], :void
  attach_function :alpinocorpus_is_valid_query, [:pointer, :string], :int

  class Reader
    include Enumerable
    include EntriesIterate

    def initialize(path)
      @reader = AlpinoCorpus::alpinocorpus_open(path)

      if @reader.null?
        raise RuntimeError, "Could not open corpus."
      end

      ObjectSpace.define_finalizer(self, self.class.finalize(@reader))
    end

    def each(&blk)
      iter = AlpinoCorpus::alpinocorpus_entry_iter(@reader)
      if iter.null?
        raise RuntimeError, "Could retrieve entries."
      end

      entriesIterate(iter, &blk)

      self
    end

    def read(name)
      strPtr = AlpinoCorpus::alpinocorpus_read(@reader, name)
      
      if strPtr.null?
        raise RuntimeError, "Could not read entry."
      end

      str = strPtr.get_string(0)

      AlpinoCorpusLibC::free(strPtr)

      str
    end

    def query(query)
      Query.new(@reader, query)
    end

    def validQuery?(query)
      AlpinoCorpus::alpinocorpus_is_valid_query(@reader, query) == 1
    end

    def self.finalize(reader)
      proc { AlpinoCorpus::alpinocorpus_close(reader) }
    end
  end

  class Query
    include Enumerable
    include EntriesIterate

    def initialize(reader, query)
      @reader = reader
      @query = query
    end

    def each(&blk)
      iter = AlpinoCorpus::alpinocorpus_query_iter(@reader, @query)
      if iter.null?
        raise RuntimeError, "Could not execute query."
      end

      entriesIterate(iter, &blk)

      self
    end
  end
end

private

module AlpinoCorpusLibC
    extend FFI::Library
    ffi_lib FFI::Library::LIBC

    attach_function :free, [:pointer], :void
end
