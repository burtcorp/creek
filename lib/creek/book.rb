require 'zip/filesystem'
require 'nokogiri'
require 'date'
require 'open-uri'

module Creek
  class Creek::Book
    attr_reader :files,
                :sheets,
                :shared_strings,
                :with_headers,
                :workbook_rels_by_type,
                :workbook_rels_by_id

    DATE_1900 = Date.new(1899, 12, 30).freeze
    DATE_1904 = Date.new(1904, 1, 1).freeze

    def initialize path, options = {}
      check_file_extension = options.fetch(:check_file_extension, true)
      if check_file_extension
        extension = File.extname(options[:original_filename] || path).downcase
        raise 'Not a valid file format.' unless (['.xlsx', '.xlsm'].include? extension)
      end
      path = download_file(path) if options[:remote]
      @files = Zip::File.open(path)
      parse_workbook_path
      parse_workbook_rels
      @shared_strings = SharedStrings.new(self)
      @with_headers = options.fetch(:with_headers, false)
    end

    def sheets
      doc = @files.file.open @workbook_path
      xml = Nokogiri::XML::Document.parse doc
      namespaces = xml.namespaces

      cssPrefix = ''
      namespaces.each do |namespace|
        if namespace[1] == 'http://schemas.openxmlformats.org/spreadsheetml/2006/main' && namespace[0] != 'xmlns' then
          cssPrefix = namespace[0].split(':')[1]+'|'
        end
      end

      @sheets = xml.css(cssPrefix+'sheet').map do |sheet|
        sheetfile = @workbook_rels_by_id[sheet.attr("r:id")]
        sheet = Sheet.new(
          self,
          sheet.attr("name"),
          sheet.attr("sheetid"),
          sheet.attr("state"),
          sheet.attr("visible"),
          sheet.attr("r:id"),
          sheetfile
        )
        sheet.with_headers = with_headers
        sheet
      end
    end

    def style_types
      @style_types ||= Creek::Styles.new(self).style_types
    end

    def close
      @files.close
    end

    def base_date
      @base_date ||=
      begin
        # Default to 1900 (minus one day due to excel quirk) but use 1904 if
        # it's set in the Workbook's workbookPr
        # http://msdn.microsoft.com/en-us/library/ff530155(v=office.12).aspx
        result = DATE_1900 # default

        doc = @files.file.open @workbook_path
        xml = Nokogiri::XML::Document.parse doc
        xml.css('workbookPr[date1904]').each do |workbookPr|
          if workbookPr['date1904'] =~ /true|1/i
            result = DATE_1904
            break
          end
        end

        result
      end
    end

    private

    def download_file(url)
      # OpenUri will return a StringIO if under OpenURI::Buffer::StringMax
      # threshold, and a Tempfile if over.
      downloaded = URI(url).open
      if downloaded.is_a? StringIO
        path = Tempfile.new(['creek-file', '.xlsx']).path
        File.binwrite(path, downloaded.read)
        path
      else
        downloaded.path
      end
    end

    def parse_workbook_path
      rels_file = @files.file.open '_rels/.rels'
      rels_xml = Nokogiri::XML::Document.parse(rels_file).css('Relationship')
      rel = rels_xml.find { |el| el.attr('Type') == "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" }
      @workbook_path = rel.attr('Target')
    end

    def parse_workbook_rels
      @workbook_rels_by_id = {}
      @workbook_rels_by_type = {}
      workbook_dirname, slash, workbook_basename = @workbook_path.rpartition('/')
      workbook_rels_file = @files.file.open "#{workbook_dirname}#{slash}_rels/#{workbook_basename}.rels"
      Nokogiri::XML::Document.parse(workbook_rels_file).css('Relationship').each do |rel|
        target = rel.attr('Target')
        target = "#{workbook_dirname}#{slash}#{target}" unless target.start_with?('/')
        @workbook_rels_by_id[rel.attr('Id')] = target
        @workbook_rels_by_type[rel.attr('Type')] = target
      end
    end
  end
end
