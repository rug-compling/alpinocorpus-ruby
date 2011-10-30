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
  # Reader for Alpino treebanks.
  class Reader
    include Enumerable
    include EntriesIterate

    # call-seq:
    #    Reader::open(path) -> reader<br/>
    #    Reader::open(path) { |reader| block } -> nil
    #
    # Constructs a corpus reader, opening the corpus at _path_. The
    # corpus can be one of the following types:
    #
    # * Dact (DBXML)
    # * Compact corpus
    # * Directory with XML files
    def self.open(path)
      if block_given?
        r = Reader.new(path)
        begin
          yield r
        ensure
          r.close
        end
      else
        Reader.new(path)
      end
    end

    # call-seq: Reader.new(path)
    #
    # Constructs a corpus reader, opening the corpus at _path_. The
    # corpus can be one of the following types:
    #
    # * Dact (DBXML)
    # * Compact corpus
    # * Directory with XML files
    def initialize(path)
      @open = false
      @reader = AlpinoCorpusFFI::alpinocorpus_open(path)

      if @reader.null?
        raise RuntimeError, "Could not open corpus."
      end

      @open = true

      ObjectSpace.define_finalizer(self, self.class.finalize(self))
    end

    # call-seq:
    #    read.close -> reader
    #
    # Close a reader.
    def close
      if @open
        AlpinoCorpusFFI::alpinocorpus_close(@reader)
        @open = false
      end

      self
    end

    # call-seq:
    #   reader.each {|entry| block} -> reader
    #
    # Execute a code block for each corpus entry name. 
    def each(&blk)
      check_reader

      iter = AlpinoCorpusFFI::alpinocorpus_entry_iter(@reader)
      if iter.null?
        raise RuntimeError, "Could retrieve entries."
      end

      entriesIterate(iter, &blk)

      self
    end

    # call-seq:
    #   reader.is_open? -> true or false
    #
    # Check whether the reader is open.
    def is_open?
      @open
    end

    # call-seq:
    #   reader.read(entry[, markers]) -> data
    #
    # Reads an entry from the corpus. Nodes matching a query can be marked
    # by providing a list of MarkerQuery.
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

    # call-seq:
    #   reader.query(q) -> query
    #
    # Returns a Query instance for the given query _q_.
    def query(query)
      check_reader

      Query.new(self, @reader, query)
    end

    # call-seq:
    #   reader.valid_query?(query) -> bool
    #
    # Validate an XPath query using _reader_.
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

    def self.finalize(reader) # :nodoc:
      proc { reader.close }
    end
  end

  # Queries over Reader instances.
  class Query
    include Enumerable
    include EntriesIterate

    private

    def initialize(rReader, reader, query) # :nodoc:
      @rReader = rReader
      @reader = reader
      @query = query
    end

    public

    # call-seq:
    #   query.each {|entry| block} -> query
    #
    # Execute a code block for each corpus entry name (matching the query). 
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
