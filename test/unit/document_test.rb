require File.dirname(__FILE__) + '/../test_helper'
require 'fileutils'
class DocumentTest < Test::Unit::TestCase
  include ZenaTestUnit

  def test_create_with_file
    without_files('/data/test/pdf') do
      visitor(:ant)
      doc = secure(Document) { Document.create( :parent_id=>items_id(:cleanWater),
                                                :name=>'report', 
                                                :file => uploaded_pdf('water.pdf') ) }
      assert_kind_of Document , doc
      assert ! doc.new_record? , "Not a new record"
      assert_equal "report", doc.name
      assert_equal "report", doc.title
      assert_equal "report.pdf", doc.filename
      assert_equal 'pdf', doc.ext
      v = doc.send :version
      assert ! v.new_record? , "Version is not a new record"
      assert_not_nil v.file_ref , "File_ref is set"
      file = doc.file
      assert_kind_of DocFile , file
      assert_equal "/pdf/#{doc.v_id}/report.pdf", file.path
      assert File.exist?("#{RAILS_ROOT}/data/test#{file.path}")
      assert_equal File.stat("#{RAILS_ROOT}/data/test#{file.path}").size, doc.filesize
    end
  end
  
  def test_create_with_bad_filename
    preserving_files('/data/test/pdf') do
      visitor(:ant)
      doc = secure(Document) { Document.create( :parent_id=>items_id(:cleanWater),
                                                :title => 'My new project',
                                                :file => uploaded_pdf('water.pdf', 'stupid.jpg') ) }
      assert_kind_of Document , doc
      assert ! doc.new_record? , "Not a new record"
      assert_equal "stupid.pdf", doc.name
      assert_equal "My new project", doc.title
      v = doc.send :version
    end
  end
  
  def test_create_with_duplicate_name
    preserving_files('/data/test/pdf') do
      visitor(:ant)
      doc = secure(Document) { Document.create( :parent_id=>items_id(:wiki),
        :title => 'bird.jpg',
        :file => uploaded_pdf('bird.jpg') ) }
        assert_kind_of Document , doc
        assert_equal 'bird', doc.name
        assert doc.new_record? , "Not saved"
        assert_equal "bird", doc.name
        assert_equal "has already been taken", doc.errors[:name]
      end
  end
  
  def test_create_with_bad_filename
    preserving_files('/data/test/pdf') do
      visitor(:ant)
      doc = secure(Document) { Document.create( :parent_id=>items_id(:cleanWater),
        :name => 'stupid.jpg',
        :file => uploaded_pdf('water.pdf') ) }
      assert_kind_of Document , doc
      assert ! doc.new_record? , "Not a new record"
      assert_equal "stupid", doc.name
      assert_equal "stupid", doc.title
      assert_equal "stupid.pdf", doc.filename
    end
  end
  
  def get_with_full_path
    visitor(:tiger)
    doc = secure(Document) { Document.find_by_path( user_id, user_groups, lang, "/projects/cleanWater/water.pdf") }
    assert_kind_of Document, doc
    assert_equal "/projects/cleanWater/water.pdf", doc.fullpath
  end
  
  def test_image
    visitor(:tiger)
    doc = secure(Document) { Document.find( items_id(:water_pdf) ) }
    assert ! doc.image?, 'Not an image'
    doc = secure(Document) { Document.find( items_id(:bird_jpg) )  }
    assert doc.image?, 'Is an image'
  end
  
  def test_img_tag
    visitor(:tiger)
    doc = secure(Document) { Document.find( items_id(:water_pdf) ) }
    assert_nothing_raised { doc.img_tag; doc.img_tag('std') }
  end
  
  def test_filesize
    visitor(:tiger)
    doc = secure(Document) { Document.find( items_id(:water_pdf) ) }
    assert_nothing_raised { doc.filesize }
  end
  
  def test_file
    visitor(:tiger)
    doc = secure(Document) { Document.find( items_id(:water_pdf) ) }
    file = nil
    assert_nothing_raised { file = doc.file }
    assert_kind_of DocFile, file
  end
  
  def test_create_with_text_file
    preserving_files('/data/test/txt') do
      visitor(:ant)
      doc = secure(Document) { Document.create( :parent_id=>items_id(:cleanWater),
        :name => 'stupid.jpg',
        :file => uploaded_text('some.txt') ) }
      assert_kind_of Document , doc
      assert ! doc.new_record? , "Not a new record"
      assert_equal "stupid", doc.name
      assert_equal "stupid", doc.title
      assert_equal 'txt', doc.ext
    end
  end
  
  def test_change_file
    preserving_files('/data/test/pdf') do
      visitor(:tiger)
      doc = secure(Document) { Document.find(items_id(:water_pdf)) }
      assert_equal 29279, doc.filesize
      assert_equal '/pdf/15/water.pdf', doc.file.path
      assert doc.update_redaction(:file=>uploaded_pdf('forest.pdf'), :title=>'forest gump'), "Can change file"
      doc = secure(Item) { items(:water_pdf) }
      assert_equal 'forest gump', doc.title
      assert_equal 'pdf', doc.ext
      assert_equal 63569, doc.filesize
      last_id = Version.find(:first, :order=>"id DESC").id
      assert_not_equal 15, last_id
      assert_equal "/pdf/#{last_id}/water.pdf", doc.file.path
      assert doc.update_redaction(:file=>uploaded_pdf('water.pdf')), "Can change file"
      doc = secure(Item) { items(:water_pdf) }
      assert_equal 'forest gump', doc.title
      assert_equal 'pdf', doc.ext
      assert_equal 29279, doc.filesize
      assert_equal "/pdf/#{last_id}/water.pdf", doc.file.path
    end
  end
      
end
