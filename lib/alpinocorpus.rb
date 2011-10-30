require 'ffi'

module EntriesIterate # :nodoc:
  def entriesIterate(iter)
    begin
      # Retrieve iterate value as a pointer, we have to free it.
      strPtr = AlpinoCorpusFFI::alpinocorpus_iter_value(iter)

      # Convert and yield the string.
      str = strPtr.get_string(0)
      yield str

      # Free the C string.
      AlpinoCorpusLibC::free(strPtr)
    end while AlpinoCorpusFFI::alpinocorpus_iter_next(@reader, iter) != 0

    AlpinoCorpusFFI::alpinocorpus_iter_destroy(iter)
  end
end


module AlpinoCorpus
  class Reader
    include Enumerable
    include EntriesIterate

    def initialize(path)
      @open = false
      @reader = AlpinoCorpusFFI::alpinocorpus_open(path)

      if @reader.null?
        raise RuntimeError, "Could not open corpus."
      end

      @open = true

      ObjectSpace.define_finalizer(self, self.class.finalize(self))
    end

    def close
      if @open
        AlpinoCorpusFFI::alpinocorpus_close(@reader)
        @open = false
      end

      self
    end

    def each(&blk)
      check_reader

      iter = AlpinoCorpusFFI::alpinocorpus_entry_iter(@reader)
      if iter.null?
        raise RuntimeError, "Could retrieve entries."
      end

      entriesIterate(iter, &blk)

      self
    end

    def is_open?
      @open
    end

    def read(name)
      check_reader

      strPtr = AlpinoCorpusFFI::alpinocorpus_read(@reader, name)
      
      if strPtr.null?
        raise RuntimeError, "Could not read entry."
      end

      str = strPtr.get_string(0)

      AlpinoCorpusLibC::free(strPtr)

      str
    end

    def query(query)
      check_reader

      Query.new(self, @reader, query)
    end

    def valid_query?(query)
      check_reader

      AlpinoCorpusFFI::alpinocorpus_is_valid_query(@reader, query) == 1
    end

    def check_reader # :nodoc:
      if !@open
        raise RuntimeError, "closed reader"
      end
    end

    private

    def self.finalize(reader)
      proc { reader.close }
    end
  end

  class Query
    include Enumerable
    include EntriesIterate

    private

    def initialize(rReader, reader, query)
      @rReader = rReader
      @reader = reader
      @query = query
    end

    public

    def each(&blk)
      @rReader.check_reader

      iter = AlpinoCorpusFFI::alpinocorpus_query_iter(@reader, @query)
      if iter.null?
        raise RuntimeError, "Could not execute query."
      end

      entriesIterate(iter, &blk)

      self
    end
  end
end

module AlpinoCorpusFFI # :nodoc:
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
end

module AlpinoCorpusLibC # :nodoc:
    extend FFI::Library
    ffi_lib FFI::Library::LIBC

    attach_function :free, [:pointer], :void
end
