# This class stores version text for #Document. If a translation or new redaction of the text
# is created, both the new and the old #DocVersion refer to the same file (#DocFile)
class DocVersion < Version
  validate :valid_file
  validate_on_update :can_update_file

  after_create :create_doc_file
  before_update :update_file_ref
  
  # format is ignored here
  def img_tag(format=nil)
    ext = item.ext
    unless File.exist?("#{RAILS_ROOT}/public/images/ext/#{ext}.png")
      ext = 'other'
    end
    unless format
      # img_tag from extension
      "<img src='/images/ext/#{ext}.png' width='32' height='32' class='icon'/>"
    else
      img = ImageBuilder.new(:path=>"#{RAILS_ROOT}/public/images/ext/#{ext}.png", :width=>32, :height=>32)
      img.transform!(format)
      path = "#{RAILS_ROOT}/public/images/ext/"
      filename = "#{ext}-#{format}.png"
      unless File.exist?(File.join(path,filename))
        # make new image with the format
        unless File.exist?(path)
          FileUtils::mkpath(path)
        end
        if img.dummy?
          File.cp("#{RAILS_ROOT}/public/images/ext/#{ext}.png", "#{RAILS_ROOT}/public/images/ext/#{ext}-#{format}.png")
        else
          File.open(File.join(path, filename), "wb") { |f| f.syswrite(img.read) }
        end
      end
      "<img src='/images/ext/#{filename}' width='#{img.width}' height='#{img.height}' class='#{format}'/>"
    end
  end
  
  def doc_file
    @docfile ||= file_class.find_by_version_id(self[:file_ref])
  end
  alias file doc_file
  
  def filesize; file.size; end
    
  def file_ref=(i)
    raise Zena::AccessViolation, "'file_ref' cannot be changed"
  end
  
  def file=(f)
    @file = f
  end
  
  def ext=(val)
    @ext = val
  end
  
  def filename
    "#{item.name}.#{doc_file.ext}"
  end
  
  private
  
  def set_file_ref
    self[:file_ref] ||= self[:id]
  end
  
  def valid_file
    errors.add('file', 'not set') unless @file || doc_file || !new_record?
    if @file && kind_of?(ImageVersion) && !Image.image_content_type?(@file.content_type)
      errors.add('file', 'must be an image')
    end
  end
  
  def can_update_file
    if @file && (self[:file_ref] == self[:id]) && (Version.find_all_by_file_ref(self[:id]).size > 1)
      errors.add('file', 'cannot be changed (used by other versions)')
    end
  end
  
  def create_doc_file
    if @file
      # new document or new edition with a new file
      self[:file_ref] = self[:id]
      DocVersion.connection.execute "UPDATE versions SET file_ref=id WHERE id=#{id}"
      file_class.create(:version_id=>self[:id], :file=>@file, :ext=>@ext)
    end
  end
  
  def update_file_ref
    if @file
      # redaction with a new file
      if self[:file_ref] == self[:id]
        # our own file changed
        doc_file.file = @file
        doc_file.ext  = @ext
        doc_file.save
      else
        self[:file_ref] = self[:id]
        file_class.create(:version_id=>self[:id], :file=>@file, :ext=>@ext)
      end
    end
  end
  
  def file_class
    DocFile
  end
end
