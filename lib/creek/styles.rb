module Creek
  class Styles
    attr_accessor :book
    def initialize(book)
      @book = book
    end

    def path
      @book.workbook_rels_by_type["http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles"]
    end

    def styles_xml
      @styles_xml ||= begin
        if path
          doc = @book.files.file.open path
          Nokogiri::XML::Document.parse doc
        end
      end
    end

    def style_types
      @style_types ||= begin
        Creek::Styles::StyleTypes.new(styles_xml).call
      end
    end
  end
end
