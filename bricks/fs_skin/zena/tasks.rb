
namespace :fs_skin do
  desc 'rebuild fs_skin index'
  task :index => :environment do
    # Make sure all bricks are loaded before executing the index rebuild
    Zena::Use.upgrade_class('Site')
  
    include Zena::Acts::Secure
    if ENV['HOST']
      sites = [Site.find_by_host(ENV['HOST'])]
    else
      sites = Site.master_sites
    end
    
    sites.each do |site|
      setup_visitor(site.any_admin, site)
      if ENV['WORKER'] == 'false' || RAILS_ENV == 'test'
        # We avoid SiteWorker.
        site.rebuild_fs_skin_index
      else
        # We try to use the site worker.
        Zena::SiteWorker.perform(site, :rebuild_fs_skin_index, nil)
      end
    end
  end
end