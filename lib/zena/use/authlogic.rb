module Zena
  module Use
    module Authlogic
      class RenderSession < ActiveRecord::Base
        set_table_name :sessions
      end

      module Common

        def visitor
           Thread.current[:visitor]
         end

      end # Common

      module ControllerMethods

        def self.included(base)
          base.before_filter :set_visitor, :force_authentication?, :redirect_to_https
        end

        include Common
        
        def ssl_request?
          request.ssl? || request.headers['X_FORWARDED_PROTO'] == 'https'
        end

        private

          def save_after_login_path
            # prevent redirect to favicon or css
            return unless request.format == Mime::HTML
            path = params[:path]
            if path && path.last =~ /\.(.+)\Z/
              return if $1 != 'html'
            end

            session[:after_login_path] = request.parameters
          end

          def set_visitor
            forge_cookie_with_http_auth
            unless site = Site.find_by_host(request.host)
              raise ActiveRecord::RecordNotFound.new("host not found #{request.host}")
            end

            # We temporarily set the locale so that any error message raised during authentification can be properly shown
            ::I18n.locale = site.default_lang

            User.send(:with_scope, :find => {:conditions => ['site_id = ?', site.id]}) do
              if user = token_visitor || registered_visitor || anonymous_visitor(site)
                user.asset_host = @asset_host
                # Make sure we load alias site in visitor
                setup_visitor(user, site)
              end
            end
          end

          # Secured in site with scope in set_visitor
          def registered_visitor
            visitor_session && visitor_session.user
          end

          def visitor_session
            UserSession.find
          end

          def anonymous_visitor(site)
            site.anon.tap do |v|
              v.ip = request.headers['REMOTE_ADDR']
            end
          end

          def check_is_admin
            raise ActiveRecord::RecordNotFound unless visitor.is_admin?
            @admin = true
          end
          
          # Returns true if the site is not in readonly mode.
          def check_not_readonly
            raise ActiveRecord::ReadOnlyRecord if current_site.site_readonly?
          end

          def lang
            visitor.lang
          end

          # Secured in site with scope in set_visitor
          def token_visitor
            if user_token = (request.headers['HTTP_X_AUTHENTICATION_TOKEN'] || params[:user_token])
              User.find_by_single_access_token(user_token)
            end
          end
          
          # Create a fake cookie based on HTTP_AUTH using session_id and render_token. This is
          # only used for requests from localhost (asset host).
          def forge_cookie_with_http_auth
            if Zena::LOCAL_IPS.include?(request.headers['REMOTE_ADDR']) &&
               (Zena::ASSET_PORT.to_i == 0 || request.port.to_i == Zena::ASSET_PORT)
              authenticate_with_http_basic do |login, password|
                # login    = visitor.id
                # password = persistence_token
                @asset_host = true
                # forge cookie
                cookies['user_credentials'] = "#{password}::#{login}"
              end
            end
          end

          # Secured in site with scope in set_visitor
          def http_visitor(site)
            if request.format == Mime::XML
              # user must be an authentication token
              authenticate_or_request_with_http_basic do |login, password|
                User.find_by_single_access_token(password)
              end
            elsif site.http_auth # HTTP_AUTH disabled for now.
              user = User.find_allowed_user_by_login(login)
              user if (user && user.valid_password?(password))
            end
          end

          def force_authentication?
            if visitor.is_anon?
              # Anonymous visitor has more limited access rights.

              if current_site.authentication? || params[:prefix] == AUTHENTICATED_PREFIX
                # Ask for login
                save_after_login_path
                redirect_to login_path
              elsif request.format == Mime::XML && (self != NodesController || !params[:prefix])
                # Allow xml without :prefix in NodesController because it is rendered with zafu.

                # Authentication token required for xml.
                render :xml => [{:message => 'Authentication token needed.'}].to_xml(:root => 'errors'), :status => 401
              end
            end
          end
          
          # Force https if ssl_on_auth is enabled. This method is overwriten in UserSessionsController.
          def redirect_to_https
            if current_site.ssl_on_auth
              if !ssl_request? && !visitor.is_anon? && !local_request?
                # Note that this does not work for PUT or DELETE verbs...
                redirect_to(params.merge({:protocol => 'https'}), :flash => flash)
              elsif ssl_request? && visitor.is_anon?
                redirect_to(params.merge({:protocol => 'http'}), :flash => flash)
              end
            end
          end
      end

      module ViewMethods

        include Common

      end # ViewMethods

    end # Authlogic
  end # Use
end # Zena