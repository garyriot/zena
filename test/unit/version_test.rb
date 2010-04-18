require 'test_helper'
class VersionTest < Zena::Unit::TestCase
  context 'With a logged in visitor' do
    setup do
      login(:tiger)
    end

    context 'a version' do
      subject do
        versions(:status_en)
      end

      context 'on author' do
        should 'return a Contact' do
          assert_kind_of Contact, subject.author
        end

        should 'return the contact node of the author' do
          assert_equal nodes_id(:ant), subject.author[:id]
        end
      end # on author
    end # a version


    context 'a redaction' do
      subject do
        versions(:opening_red_fr)
      end
    end # a redaction

    context 'setting v_lang' do
      context 'on node creation' do
        setup do
          @node = secure!(Page) { Page.create(:v_lang => 'io', :parent_id => nodes_id(:status), :name => 'hello', :title => '')}
        end

        should 'not create record if lang is not allowed' do
          assert @node.new_record?
        end

        should 'return an error on v_lang' do
          assert @node.errors[:v_lang].any?
        end
      end
    end # setting v_lang

    context 'updating a version' do
      setup do
        @node = secure!(Node) { nodes(:status) }
      end

      subject do
        @node.version
      end

      should 'not allow setting node_id' do
        subject.update_attributes(:node_id => nodes_id(:lake))
        assert_equal nodes_id(:status), subject.node_id
      end

      should 'not allow setting attachment_id' do
        subject.update_attributes(:attachment_id => attachments_id(:bird_jpg_en))
        assert_nil subject.attachment_id
      end

      should 'not allow setting site_id' do
        subject.update_attributes(:site_id => sites_id(:ocean))
        assert_equal sites_id(:zena), subject.site_id
      end

      should 'not allow setting number' do
        subject.update_attributes(:number => 5)
        assert_equal 1, subject.number
      end
    end # updating a version

    context 'updating a node' do
      subject do
        secure!(Node) { nodes(:tiger) }
      end

      should 'increase version number' do
        assert_difference('subject.version.number', 1) do
          subject.update_attributes(:name => 'John')
        end
      end

      should 'create a new version' do
        assert_difference('Version.count', 1) do
          subject.update_attributes(:first_name => 'Foobar')
        end
      end
    end # updating a node
  end # With a logged in visitor

  context 'A new version' do
    should 'not allow setting node_id' do
      version = Version.new(:node_id => 1234)
      assert_nil version.node_id
    end

    should 'not allow setting attachment_id' do
      version = Version.new(:attachment_id => attachments_id(:bird_jpg_en))
      assert_nil version.attachment_id
    end

    should 'not allow setting site_id' do
      version = Version.new(:site_id => sites_id(:ocean))
      assert_nil version.site_id
    end

    should 'not allow setting number' do
      version = Version.new(:number => 5)
      assert_equal 1, version.number
    end

    should 'set site_id on save' do
      version = Version.new(:status => Zena::Status[:red])
      version.node = secure!(Node) { nodes(:status) }
      assert version.save
      assert_equal sites_id(:zena), version.site_id
    end

    should 'not save if node is not set' do
      version = Version.new(:status => Zena::Status[:red])
      assert !version.save
      assert_equal "can't be blank", version.errors[:node]
    end
  end # A new version

  def version(sym)
    secure!(Node) { nodes(sym) }.version
  end

  def test_update_content_one_version
    preserving_files("test.host/data") do
      login(:ant)
      visitor.lang = 'en'
      node = secure!(Node) { nodes(:forest_pdf) }
      assert_equal Zena::Status[:red], node.version.status
      assert_equal versions_id(:forest_pdf_en), node.version_id
      assert_equal 63569, node.size
      # single redaction in redit time
      node.version.created_at = Time.now
      assert node.update_attributes(:file=>uploaded_pdf('water.pdf')), 'Can edit node'
      # version and content object are the same
      assert_equal versions_id(:forest_pdf_en), node.version_id
      # content changed
      assert_equal 29279, node.size
      assert_kind_of File, node.file
      assert_equal 29279, node.file.stat.size
    end
  end

  def test_remap_master_version_if_many_use_same_content
    preserving_files("test.host/data") do
      login(:ant)
      visitor.lang = 'fr'
      node = secure!(Node) { nodes(:forest_pdf) }
      old_vers_id = node.version.id
      # ant's english redaction
      assert_equal 'en', node.version.lang
      content_id_before_move = node.id

      # 1. Create a new version in french
      assert node.update_attributes(:title=>'les arbres')

      assert node.propose # only proposed/published versions block
      assert_equal 'fr', node.version.lang

      # new redaction for french
      assert_not_equal node.version.id, old_vers_id

      # 2. New redaction points to old content
      assert_equal     node.version.content_id, old_vers_id

      login(:ant)
      visitor.lang = 'en'
      node = secure!(Node) { nodes(:forest_pdf) }

      # 3. Edit ant's original (english) redaction
      assert_equal old_vers_id, node.version.id

      # edit content (should move content's master_version to other version and create a new content)
      node.version.created_at = Time.now # force redit time
      assert node.update_attributes(:file=>uploaded_pdf('water.pdf'))
      assert_nil node.version.content_id # we have our own content
      assert_equal node.version.id, node.version_id
      # this is still the original (english) version
      assert_equal old_vers_id, node.version.id

      login(:ant)
      visitor.lang = 'fr'
      node = secure!(Node) { nodes(:forest_pdf) }

      # 4. The content has become our own
      assert_equal content_id_before_move, node.id
      assert_nil node.version.content_id
      assert_equal node.version.id, node.version_id
    end
  end

  def test_dynamic_attributes
    login(:tiger)
    node = secure!(Node) { nodes(:status) }
    version = node.send(:redaction)
    assert_nothing_raised { version.prop['zucchini'] = 'courgettes' }
    assert_nothing_raised { version.dyn_attributes = {'zucchini' => 'courgettes' }}
    assert_equal 'courgettes', version.prop['zucchini']
    assert node.save

    node = secure!(Node) { nodes(:status) }
    version = node.version
    assert_equal 'courgettes', version.prop['zucchini']
  end

  def test_clone
    login(:tiger)
    node = secure!(Node) { nodes(:status) }
    assert node.update_attributes(:d_whatever => 'no idea')
    assert_equal 'no idea', node.version.prop['whatever']
    version1_id = node.version[:id]
    assert node.publish
    version1_publish_from = node.version.publish_from

    node = secure!(Node) { nodes(:status) }
    assert node.update_attributes(:d_other => 'funny')
    version2_id = node.version[:id]
    assert_not_equal version1_id, version2_id
    assert_equal 'no idea', node.version.prop['whatever']
    assert_equal 'funny', node.version.prop['other']
    assert_equal version1_publish_from, node.version.publish_from
  end

  def test_would_edit
    v = versions(:zena_en)
    assert v.would_edit?('title' => 'different')
    assert v.would_edit?('dyn_attributes' => {'foo' => 'different'})
    assert !v.would_edit?('title' => v.title)
    assert !v.would_edit?('status' => Zena::Status[:red])
    assert !v.would_edit?('illegal_field' => 'whatever')
    assert !v.would_edit?('node_id' => 'whatever')
  end

  def test_would_edit_content
    v = versions(:ant_en)
    assert v.would_edit?('content_attributes' => {'name' => 'different'})
    assert !v.would_edit?('content_attributes' => {'name' => v.content.name})
  end

  def test_new_version_is_edited
    v = Version.new
    assert v.edited?
    v.title = 'hooo'
    assert v.edited?
  end

  def test_edited
    v = versions(:zena_en)
    assert !v.edited?
    v.status = 999
    assert !v.edited?
    v.title = 'new title'
    assert v.edited?
  end

  def test_edited_changed_content
    v = versions(:ant_en)
    v.content_attributes = {'name' => 'Invicta'}
    assert !v.edited?
    v.content_attributes = {'name' => 'New name'}
    assert v.edited?
  end


  def test_set_v_lang
    login(:tiger)
    assert_equal 'en', visitor.lang
    node = secure!(Page) { Page.create(:v_lang => 'fr', :parent_id => nodes_id(:status), :name => 'hello', :title => '')}
    assert !node.new_record?
    assert_equal 'fr', node.version.lang
  end

  def test_create_version_other_lang
    login(:tiger)
    assert_equal 'en', visitor.lang
    node = secure!(Node) { nodes(:projects) }
    en_version = node.version
    assert node.update_attributes(:v_lang => 'fr', :title => 'projets')
    assert !node.new_record?
    assert_equal 'fr', node.version.lang
    assert_not_equal en_version.id, node.version.id
  end

  def test_should_parse_publish_from_date
    I18n.locale = 'fr'
    visitor.time_zone = 'Asia/Jakarta'
    v = Version.new('publish_from' => '9-9-2009 15:17')
    assert_equal Time.utc(2009,9,9,8,17), v.publish_from
  end

  context 'A visitor with write access on a redaction with dyn attributes' do
    setup do
      login(:tiger)
      node = secure(Node) { nodes(:nature) }
      node.update_attributes(:d_foo => 'bar')
      @node = secure(Node) { nodes(:nature) } # reload
    end

    should 'see dyn attribute' do
      assert_equal 'bar', @node.version.prop['foo']
    end

    should 'see be able to update dyn attribute' do
      assert @node.version.dyn.would_edit?('foo' => 'max')
      assert @node.update_attributes(:d_foo => 'max')
      @node = secure(Node) { nodes(:nature) }
      assert_equal 'max', @node.version.prop['foo']
    end
  end
end
