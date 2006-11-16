require File.dirname(__FILE__) + '/../test_helper'

class DocFileTest < Test::Unit::TestCase
  include ZenaTestUnit
  
  def test_set_file
    doc = DocFile.new
    assert_nothing_raised { doc.file = uploaded_pdf('water.pdf') }
    assert_equal 'application/pdf', doc.content_type
    assert_equal 29279, doc.size
  end
  
  def test_read
    doc = DocFile.new( :file=>uploaded_pdf('water.pdf') )
    data = nil
    assert_nothing_raised { data = doc.read }
    assert_equal data, uploaded_pdf('water.pdf').read
    doc = DocFile.new
    assert_nil doc.read
  end
  
  def test_docfile_valid_no_version
    doc = DocFile.new( :file=>uploaded_pdf('water.pdf') )
    assert !doc.save
    assert_equal 'version must exist', doc.errors[:version_id]
  end
  
  def test_docfile_valid_no_file
    doc = DocFile.new( :version_id=>11 )
    assert !doc.save
    assert_equal 'file not set', doc.errors[:base]
  end
  
  def test_filepath_without_version
    doc = DocFile.new( :file=>uploaded_pdf('water.pdf') )
    assert_raise(StandardError) { doc.send(:filepath) }
  end
  
  def test_filepath_ok
    doc = DocFile.new( :version_id=>15, :file=>uploaded_pdf('water.pdf') )
    fp = doc.send(:filepath)
    assert_equal "#{RAILS_ROOT}/data/#{RAILS_ENV}/pdf/15/water.pdf", fp
  end
  
  def test_save_file
    FileUtils::mv("#{RAILS_ROOT}/data/#{RAILS_ENV}/pdf/15/water.pdf","#{RAILS_ROOT}/data/#{RAILS_ENV}/pdf/15/water.pdf.bak")
    doc = DocFile.new( :version_id=>15, :file=>uploaded_pdf('water.pdf') )
    assert !File.exist?("#{RAILS_ROOT}/data/#{RAILS_ENV}/pdf/15/water.pdf")
    assert doc.save, "Can save"
    assert File.exist?("#{RAILS_ROOT}/data/#{RAILS_ENV}/pdf/15/water.pdf")
    assert_equal 29279, doc.size
    FileUtils::rm("#{RAILS_ROOT}/data/#{RAILS_ENV}/pdf/15/water.pdf.bak")
  end
end
