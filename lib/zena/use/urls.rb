module Zena
  module Use
    module Urls
      NODE_ACTIONS = {
        ''         => {:url => '/nodes/#{node_zip}'},
        'drive'    => {:url => '/nodes/#{node_zip}/edit'},
        'add_doc'  => {:url => '/documents/new', :query => {:parent_id => 'node_zip'}},
        'destroy'  => {:url => '/nodes/#{node_zip}', :method => 'delete'},
        'update'   => {:url => '/nodes/#{node_zip}', :method => 'put'},
        'drop'     => {:url => '/nodes/#{node_zip}/drop'},
        'unlink'   => {:url => '/nodes/#{node_zip}/link/#{node.link_id}', :method => 'delete'},
        'zafu'     => {:url => '/nodes/#{node_zip}/zafu'},
        'publish'  => {:url => '/nodes/#{node_zip}/versions/0/publish', :method => 'put'},
        'propose'  => {:url => '/nodes/#{node_zip}/versions/0/propose', :method => 'put'},
        'refuse'   => {:url => '/nodes/#{node_zip}/versions/0/refuse',  :method => 'put'},
        'edit'     => {:url => '/nodes/#{node_zip}/versions/0/edit'},
        'create'   => {:url => '/nodes', :method => 'post', :query => {:parent_id => 'node_zip'}},
      }


      ALLOWED_REGEXP = /\A(([a-zA-Z]+)([0-9]+)|([#{String::ALLOWED_CHARS_IN_URL}\-%]+))(_[a-zA-Z]+|)(=[a-z0-9]+|)(\..+|)\Z/

      module Common
        # This is directly related to the FileMatch clause in httpd.rhtml (mod_expires for apaches)
        CACHESTAMP_FORMATS = %w{ico flv jpg jpeg png gif js css swf}

        def prefix
          if visitor.is_anon?
            visitor.lang
          else
            AUTHENTICATED_PREFIX
          end
        end

        # We overwrite some url writers that might use Node so that they use
        # zip instead of id.
        NODE_ACTIONS.each do |name, definition|
          method = name.blank? ? 'node_path' : "#{name}_node_path"
          hash_str = []
          if query = definition[:query]
            query.each do |k,v|
              hash_str << ":#{k} => #{v}"
            end
          end

          if hash_str.empty?
            opts_merge = ''
          else
            opts_merge = "options = {#{hash_str.join(',')}}.merge(options)"  # {:parent_id => node_zip}.merge(options)
          end

          class_eval(%Q{
            def #{method}(node, options={})                       # def zafu_node_path(node, options={})
              return '#' unless node                              #   return '#' unless node
              node_zip = node.kind_of?(Node) ? node.zip : node    #   node_zip = node.kind_of?(Node) ? node.zip : node
              #{opts_merge}                                       #   options = {:parent_id => node.zip}.merge(options)
              append_query_params("#{definition[:url]}", options) #   append_query_params("/nodes/\#{node.zip}/zafu", options)
            end                                                   # end
          }, __FILE__, __LINE__ - 5)
        end

        # Path to remove a node link.
        def unlink_node_path(node, options={})
          return '#' unless node.can_write? && node.link_id
          node_link_path(node.zip, node.link_id, options)
        end

        # Path for a node. Options can be :format, :host and :mode.
        # ex '/en/document34_print.html'
        def zen_path(node, options={})
          return '#' unless node

          if anchor = options.delete(:anchor)
            return "#{zen_path(node, options)}##{anchor}"
          end

          opts   = options.dup
          format = opts.delete(:format)
          if format.blank?
            format = 'html'
          elsif format == 'data'
            if node.kind_of?(Document)
              format = node.ext
            else
              format = 'html'
            end
          end

          pre    = opts.delete(:prefix) || (visitor.is_anon? && opts.delete(:lang)) || prefix
          mode   = opts.delete(:mode)
          mode   = nil if mode.blank?
          if ep = opts[:encode_params]
            ep = ep.split(',').map(&:strip)
            if ep.delete('mode')
              mode ||= params[:mode]
            end
            opts[:encode_params] = ep
          end

          if host = opts.delete(:host)
            if ssl = opts.delete(:ssl)
              http = 'https'
            else
              http = http_protocol
            end
            abs_url_prefix = "#{http}://#{host}"
          else
            abs_url_prefix = ''
          end

          if node.kind_of?(Document) && format == node.ext
            if node.v_public? && !visitor.site.authentication?
              # force the use of a cacheable path for the data, even when navigating in '/oo'
              pre = node.version.lang
            end
          end

          if asset = opts.delete(:asset)
            mode   = nil
          end

          if should_cachestamp?(node, format, asset)
            stamp = make_cachestamp(node, mode)
          end

          path = if !asset && node[:id] == visitor.site.home_id && mode.nil? && format == 'html'
            "#{abs_url_prefix}/#{pre}" # index page
          elsif node[:custom_base]
            "#{abs_url_prefix}/#{pre}/" +
            basepath_as_url(node, true) +
            (mode  ? "_#{mode}"  : '')  +
            (asset ? "=#{asset}" : '')  +
            (stamp ? ".#{stamp}" : '')  +
            (format == 'html' ? '' : ".#{format}")
          else
            "#{abs_url_prefix}/#{pre}/" +
            basepath_as_url(node, false)+
            (node.klass.downcase   )    +
            (node[:zip].to_s       )    +
            (mode  ? "_#{mode}"  : '')  +
            (asset ? "=#{asset}" : '')  +
            (stamp ? ".#{stamp}" : '')  +
            ".#{format}"
          end
          append_query_params(path, opts)
        end

        def basepath_as_url(node, is_end)
          path = node.basepath
          if !path.blank?
            @home_base ||= begin
              p = Zena::Use::Ancestry.basepath_from_fullpath(current_site.home_node.fullpath)
              %r{^#{p}/?}
            end
            path = path.sub(@home_base, '')
            return '' if path.blank?
            path = path.split('/').map do |zip|
              if n = secure(Node) { Node.find_by_zip(zip) }
                n.title.url_name
              else
                nil
              end
            end.compact.join('/')
          end
          if is_end
            path
          else
            path.blank? ? '' : "#{path}/"
          end
        end

        def append_query_params(path, opts)

          if opts == {}
            path
          else
            tz = opts.delete(:tz)
            list = opts.keys.map do |k|
              # FIXME: DOC
              if k.to_s == 'encode_params'
                list = opts[k]
                list = list.split(',').map(&:strip) unless list.kind_of?(Array)
                list.map do |key|
                  value = params[key]
                  if value.kind_of?(Hash)
                    {key => value}.to_query
                  elsif value.kind_of?(Array)
                    {key => value.map{|v| v.blank? ? nil : v}.compact}.to_query
                  elsif !value.blank?
                    "#{key}=#{CGI.escape(value)}"
                  else
                    nil
                  end
                end
              elsif value = opts[k]
                if value.respond_to?(:strftime_tz,true)
                  "#{k}=#{CGI.escape(value.strftime_tz(_(Zena::Use::Dates::DATETIME), tz))}"
                elsif value.kind_of?(Hash)
                  "#{k}=#{value.to_query}"
                elsif value.kind_of?(Node)
                  "#{k}=#{value.zip}"
                elsif !value.nil?
                  "#{k}=#{CGI.escape(value.to_s)}"
                else
                  nil
                end
              else
                nil
              end
            end.flatten.compact

            # TODO: replace '&' by '&amp;' ? Or escape later ? Use h before zen_path in templates ? What about css/xls/other stuff ?
            # Best solution: use 'h' in template when set in default
            path + (list.empty? ? '' : "?#{list.sort.join('&')}")
          end
        end

        # Url for a node. Options are 'mode' and 'format'
        # ex 'http://test.host/en/document34_print.html'
        def zen_url(node, opts={})
          zen_path(node,{:host => host_with_port}.merge(opts))
        end

        # Return the path to a document's data
        def data_path(node, opts={})
          if node.kind_of?(Document)
            zen_path(node, opts.merge(:format => node.prop['ext']))
          else
            zen_path(node, opts)
          end
        end

        def cachestamp_format?(format)
          CACHESTAMP_FORMATS.include?(format)
        end

        def should_cachestamp?(node, format, asset)
          cachestamp_format?(format)
          #  &&
          # ((node.kind_of?(Document) && node.prop['ext'] == format) || asset)
        end

        def make_cachestamp(node, mode)
          str = if mode
            if node.kind_of?(Image)
              if iformat = Iformat[mode]
                "#{node.updated_at.to_i + iformat[:hash_id]}"
              else
                # random (will raise a 404 error anyway)
                "#{node.updated_at.to_i + Time.now.to_i}"
              end
            else
              # same format but different mode ? foobar_iphone.css ?
              # will not be used.
              node.updated_at.to_i.to_s
            end
          else
            node.updated_at.to_i.to_s
          end

          Digest::SHA1.hexdigest(str)[0..4]
        end

        # Url parameters (without format/mode/prefix...)
        def query_params
          res = {}
          path_params.each do |k,v|
            next if [:mode, :format, :asset, :cachestamp].include?(k.to_sym)
            res[k.to_sym] = v
          end
          res
        end

        # Url parameters (without action,controller,path,prefix)
        def path_params
          res = {}
          params.each do |k,v|
            next if [:action, :controller, :path, :prefix, :id].include?(k.to_sym)
            res[k.to_sym] = v
          end
          res
        end

        def http_protocol
          'http'
        end

        # We do not have access to the request. Port and host should be passed from view.
        def host_with_port
          current_site.host
        end
      end # Common

      module ViewAndControllerMethods
        def host_with_port
          @host_with_port ||= begin
            port = request.port
            if port.blank? || port.to_s == '80' || port.to_s == '443'
              current_site.host
            else
              "#{current_site.host}:#{port}"
            end
          end
        end

        def http_protocol
          @http_protocol ||= begin
            if request.protocol =~ /^(.*):\/\/$/
              $1
            else
              'http'
            end
          end
        end
      end

      module ControllerMethods
        include Common
        include ViewAndControllerMethods
      end # ControllerMethods

      module ViewMethods
        include Common
        include ViewAndControllerMethods
        include RubyLess
        safe_method [:url,  Node]       => {:class => String, :method => 'zen_url'}
        safe_method [:url,  Node, Hash] => {:class => String, :method => 'zen_url'}
        safe_method [:path, Node]       => {:class => String, :method => 'zen_path'}
        safe_method [:path, Node, Hash] => {:class => String, :method => 'zen_path'}

        safe_method [:zen_path, Node, Hash]     => {:class => String, :accept_nil => true}
        safe_method [:zen_path, Node]           => {:class => String, :accept_nil => true}
        safe_method [:zen_path, String, Hash]   => {:class => String, :accept_nil => true, :method => 'dummy_zen_path'}
        safe_method [:zen_path, String]         => {:class => String, :accept_nil => true, :method => 'dummy_zen_path'}


        NODE_ACTIONS.keys.each do |action|
          next if action.blank?
          safe_method [:"#{action}_node_path", Node, Hash] => {:class => String, :accept_nil => true}
          safe_method [:"#{action}_node_path", Node]       => {:class => String, :accept_nil => true}
        end

        safe_method :start_id  => {:class => Number, :method => 'start_node_zip'}

        def dummy_zen_path(string, options = {})
          if anchor = options.delete(:anchor)
            "#{string}##{anchor}"
          else
            "#{string}"
          end
        end
      end # ViewMethods

      module ZafuMethods
        include RubyLess

        # private
        safe_method :insert_dom_id => :insert_dom_id


        # Add the dom_id inside a RubyLess built method (used with make_href and ajax).
        #
        def insert_dom_id(signature)
          return nil if signature.size != 1
          {:method => @insert_dom_id, :class => String}
        end

        # creates a link. Options are:
        # :href (node, parent, project, root)
        # :tattr (translated attribute used as text link)
        # :attr (attribute used as text link)
        # <r:link href='node'><r:trans attr='lang'/></r:link>
        # <r:link href='node' tattr='lang'/>
        # <r:link update='dom_id'/>
        # <r:link page='next'/> <r:link page='previous'/> <r:link page='list'/>
        def r_link
          # If we have a contextual timezone set, pass it to @params
          if tz_name = @params[:tz]
            tz_result, tz_var = set_tz_var(tz_name)
            return tz_result unless tz_var
            @params[:tz] = 'tz'
          elsif tz_var = get_context_var('set_var', 'tz')
            @params[:tz] = 'tz'
          end

          if @params[:page] && @params[:page] != '[page_page]' # lets users use 'page' as pagination key
            pagination_links
          else
            make_link
          end
        end

        # Insert a named anchor
        def r_anchor
          @params[:anchor] ||= 'true'
          r_link
        end

        # Create a link tag.
        #
        # ==== Parameters (hash)
        #
        # * +:update+ - DOM_ID: produce an Ajax call that will update this part of the page (optional)
        # * +:default_text+ - default text to use for the link if there are no 'text', 'eval' or 'attr' params
        # * +:action+ - link action (edit, show, etc)
        #
        def make_link(options = {})
          remote_target = (options[:update] || @params.delete(:update))
          options[:action] ||= @params.delete(:action)
          confirm = @params.delete(:confirm)

          @markup.tag ||= 'a'

          if @markup.tag == 'a'
            markup = @markup
          else
            markup = Zafu::Markup.new('a')
          end

          steal_and_eval_html_params_for(markup, @params)

          href = make_href(remote_target, options)

          # This is to make sure live_id is set *inside* the <a> tag.
          if @live_param
            text = add_live_id(text_for_link, markup)
            @live_param = nil
          else
            text = text_for_link(options[:default_text])
          end

          http_method = http_method_from_action(options[:action])

          if http_method == 'delete' && method != 'unlink'
            confirm ||= '#{t("Destroy")} "#{h title}" ?'
          end

          if confirm
            confirm = ::RubyLess.translate_string(self, confirm)

            if confirm.literal
              markup.set_param(:"data-confirm", confirm.literal)
            else
              markup.set_dyn_param(:"data-confirm", "<%= fquote(#{confirm}) %>")
            end
          end

          if remote_target
            # ajax link (link_to_remote)

            # Add href to non-ajax method.
            markup.set_dyn_param(:href, "<%= #{make_href(nil, options.merge(:update => false))} %>")

            if true
              # Use onclick with Ajax.
              # FIXME: Use Zena.do so that we can use ajax stamp. This means that we write a variant of "make_href" which returns json for query parameters.
              if confirm
                markup.set_dyn_param(:onclick, "if(confirm(this.getAttribute(\"data-confirm\"))) {new Ajax.Request(\"<%= #{href} %>\", {asynchronous:true, evalScripts:true, method:\"#{http_method}\"});} return false;")
              else
                markup.set_dyn_param(:onclick, "new Ajax.Request(\"<%= #{href} %>\", {asynchronous:true, evalScripts:true, method:\"#{http_method}\"}); return false;")
              end
            else
              #### FIXME: We need the 'update' parameter to trigger a js response for delete but we ignore
              ####        the content.


              if remote_target.kind_of?(String)
                # YUCK. We should have a way to have dom_ids that do not need
                # us to look for remote_target !
                remote_target = find_target(remote_target)
              end
              # Experimental new model for javascript actions.
              # Works for 'swap' but needs more adaptations for 'edit' or other links

              hash_params = []
              (options[:query_params] || @params).each do |key, value|
                next if [:update, :href, :eval, :text, :attr, :t, :host].include?(key)
                case key
                when :anchor
                  # Get anchor and force string interpolation
                  value = "%Q{#{get_anchor_name(value)}}"
                when :publish
                  if value == 'true'
                    key = 'node[v_status]'
                    value = Zena::Status::Pub
                  else
                    next
                  end
                when :encode_params, :format, :mode, :insert, :states
                  # Force string interpolation
                  value = "%Q{#{value}}"
                else
                  if value.blank?
                    value = "''"
                  end
                end
                hash_params << "#{key.inspect} => #{value}"
              end

              if host = param(:host)
                hash_params << ":host => %Q{#{host}}"
              end

              if !hash_params.blank?
                query = RubyLess.translate(self, "{#{hash_params.join(', ')}}.to_json")
              else
                query = ''
              end

              dom_id, dom_prefix = get_dom_id(remote_target)
              markup.set_dyn_param(:onclick, %Q{return Zena.#{http_method}("<%= #{dom_id} %>",<%= #{query} %>)})
            end
          else
            markup.set_dyn_param(:href, "<%= #{href} %>")

            if http_method != 'get' || confirm
              markup.set_dyn_param(:onclick, "return Zena.m(this,#{http_method.inspect})")
            end
          end

          # We wrap without callbacks (before_wrap, after_wrap) so that the link
          # is used as raw text in these callbacks.
          markup.wrap(text)
        end


        protected

          # Get default anchor name
          def get_anchor_name(anchor_name)
            if anchor_name == 'true'
              if node.will_be?(Node)
                'node#{id}'
              elsif node.will_be?(Version)
                'version#{node.id}_#{id}'
              else
                # ???
                anchor_name
                # force compilation with Node context. Why ?
                #node_bak = @context[:node]
                #@context[:node] = node(Node)
                #  anchor_name = ::RubyLess.translate_string(self, anchor_name)
                #@context[:node] = node_bak
              end
            else
              anchor_name
            end
          end

        private

          # Build the 'href' part of a link.
          def make_href(remote_target = nil, opts = {})
            anchor = @params[:anchor]
            # if anchor && !@params[:href]
            #   # Link on same page (? Why would this be of any use ? We can write <a href='#xxx'>....</a>.)
            #   return ::RubyLess.translate(self, "%Q{##{get_anchor_name(anchor)}}")
            # end

            if opts[:action] == 'edit' && remote_target
              method = 'zafu_node_path'
            elsif NODE_ACTIONS[opts[:action]]
              method = "#{opts[:action]}_node_path"
            elsif remote_target && opts[:action] != 'destroy'
              method = 'zafu_node_path'
            else
              method = 'zen_path'
            end

            method_args = []
            hash_params = []

            if href = @params[:href]
              method_args << href
            elsif node.will_be?(Version)
              method_args << "this.node"
              hash_params << ":lang => this.lang"
            else
              method_args << '@node'
            end

            insert_ajax_args(remote_target, hash_params, opts[:action]) if remote_target

            (opts[:query_params] || @params).each do |key, value|
              next if [:update, :href, :eval, :text, :attr, :t, :host].include?(key)
              case key
              when :anchor
                # Get anchor and force string interpolation
                value = "%Q{#{get_anchor_name(value)}}"
              when :publish
                if value == 'true'
                  key = 'node[v_status]'
                  value = Zena::Status::Pub
                else
                  next
                end
              when :encode_params, :format, :mode, :insert
                # Force string interpolation
                value = "%Q{#{value}}"
              else
                if value.blank?
                  value = "''"
                end
              end
              hash_params << "#{key.inspect} => #{value}"
            end

            if host = param(:host)
              hash_params << ":host => %Q{#{host}}"
            end

            unless hash_params.empty?
              method_args << hash_params.join(', ')
            end

            method = "#{method}(#{method_args.join(', ')})"

            ::RubyLess.translate(self, method)
          end

          def insert_ajax_args(target, hash_params, action)
            hash_params << ":s => start_id"
            hash_params << ":link_id => this.link_id" if @context[:has_link_id] && node.will_be?(Node) && !node.list_context?

            # FIXME: when we have proper markup.dyn_params[:id] support,
            # we should not need this crap anymore.
            case action
            when 'edit'
              # 'each' or 'block' target in parent hierarchy
              is_list = ancestor(%w{each block}).method == 'each'
              @insert_dom_id = %Q{"#{node.dom_id(:erb => false, :list => is_list)}"}
              hash_params << ":dom_id => insert_dom_id"
              hash_params << ":t_url  => %Q{#{form_url(node.dom_prefix)}}"
              # To enable link edit fix the following line:
              # hash_params << "'node[link_id]' => link_id"
            when 'unlink', 'destroy'
              @insert_dom_id = %Q{"#{node.dom_id(:erb => false)}"}
              hash_params << ":dom_id => insert_dom_id"
              hash_params << ":t_url  => %Q{#{template_url(node.dom_prefix)}}"
            else #drop, #swap
              if target == '_page'
                # reload full page
                hash_params << ":udom_id => '_page'"
                return
              elsif target.kind_of?(String)
                # named target
                if target_block = find_target(target)
                  target = target_block
                else
                  out parser_error("Could not find target name '#{target}'.")
                  return nil
                end
              end
              @insert_dom_id, dom_prefix = get_dom_id(target)
              hash_params << ":dom_id => insert_dom_id"
              hash_params << ":t_url  => %Q{#{template_url(dom_prefix)}}"
            end
          end

          # <r:link page='next'/> <r:link page='previous'/> <r:link page='list'/>
          def pagination_links
            return parser_error("not in pagination scope") unless pagination_key = get_context_var('paginate', 'key')
            page_direction = @params.delete(:page)
            case page_direction
            when 'previous', 'next'
              current      = get_context_var('paginate', 'current')
              count        = get_context_var('paginate', 'count')
              prev_or_next = get_var_name('paginate', page_direction)

              if page_direction == 'previous'
                cond = "#{prev_or_next} = (#{current} > 1 ? #{current} - 1 : nil)"
              else
                cond = "#{prev_or_next} = (#{count} - #{current} > 0 ? #{current} + 1 : nil)"
              end

              # previous_page // next_page
              set_context_var('set_var', "#{page_direction}_page",
                RubyLess::TypedString.new(prev_or_next, :class => Number, :nil => true)
              )

              unless descendant('link')
                # Do not wrap twice
                link = {
                  :href => '@node',
                  :eval => "#{page_direction}_page",
                  pagination_key => "#{page_direction}_page",
                }.merge(@params)
                # <r:link href='@node' p='next_page' eval='next_page'/>
                wrap_in_block :method => 'link', :params => link
              end

              out expand_if(cond)
            when 'list'

              node_count  = get_context_var('paginate', 'nodes')
              page_count  = get_context_var('paginate', 'count')
              curr_page   = get_context_var('paginate', 'current')
              page_number = get_var_name('paginate', 'page')
              page_join   = get_var_name('paginate', 'join')
              page_name   = get_var_name('paginate', 'page_name')
              # give access to page_name
              # FIXME: DOC
              set_context_var('set_var', 'page_name', RubyLess::TypedString.new(page_name, String))

              if @blocks == [] || (@blocks.size == 1 && !@blocks.first.kind_of?(String) && @blocks.first.method == 'else')
                # We need to insert the default 'link' tag: <r:link href='@node' #{pagination_key}='#{this}' ... do='page_name'/>
                link = {}
                @params.each do |k,v|
                  next if [:tag, :page, :join, :page_count].include?(k)
                  # transfer params
                  link[k] = v
                end
                tag = @params[:tag]

                link[:html_tag] = tag if tag
                link[:href] = '@node'
                link[:eval] = 'page_name'
                link[pagination_key.to_sym] = 'this'

                # <r:link href='@node' p='#{page_name}' ... eval='page_name'/>
                add_block :method => 'link', :params => link
              end

              if !descendant('else')
                else_tag = {:method => 'else', :text => "#{@markup.space_before}<r:this/>"}
                else_tag[:tag] = tag if tag
                add_block else_tag
                # Clear cached descendants
                @all_descendants = nil
              end
              out "<% page_numbers(#{curr_page}, #{page_count}, #{(@params[:join] || ' ').inspect}, #{@params[:page_count] ? @params[:page_count].to_i : 'nil'}) do |#{page_number}, #{page_join}, #{page_name}| %>"
              out "<%= #{page_join} %>"
              with_context(:node => node.move_to(page_number, Number)) do
                out expand_if("#{page_number} != #{curr_page}")
              end
              out "<% end %>"
            else
              parser_error("unkown option for 'page' #{@params[:page].inspect} should be ('previous', 'next' or 'list')")
            end
          end

          def text_for_link(default = nil)

            if dynamic_blocks?
              expand_with
            else
              method = get_attribute_or_eval(false)

              if !method && (@params.keys & [:attr, :eval, :text, :t]) != []
                out @errors.last
              end

              if method
                if method.opts[:html_safe]
                  method.literal || "<%= #{method} %>"
                else
                  method.literal ? ::ERB::Util.html_escape(method.literal) : "<%=h #{method} %>"
                end
              elsif default
                default
              elsif node.will_be?(Node)
                "<%=h #{node(Node)}.prop['title'] %>"
              elsif node.will_be?(Version)
                "<%=h #{node(Version)}.node.prop['title'] %>"
              elsif node.will_be?(Link)
                "<%=h #{node(Link)}.name %>"
              else
                _('edit')
              end
            end
          end

          # Return the HTTP verb to use for the given action.
          def http_method_from_action(action)
            (NODE_ACTIONS[action] || {})[:method] || 'get'
          end
      end # ZafuMethods
    end # Urls
  end # Use
end # Zena
