module ZenaTestController
  
  def init_controller
    @request    = ActionController::TestRequest.new
    @response   = ActionController::TestResponse.new
    @controller.instance_eval { @session = {}; @params = {}; @url = ActionController::UrlRewriter.new( @request, {} )}
    @controller.instance_variable_set(:@response, @response)
  end

  def login(visitor=:ant)
    @controller_bak = @controller
    @controller = LoginController.new
    post 'login', :user=>{:login=>visitor.to_s, :password=>visitor.to_s}
    @controller_bak.instance_variable_set(:@session, @controller.instance_variable_get(:@session) )
    @controller = @controller_bak
  end
  
  def logout
    @controller_bak = @controller
    @controller = LoginController.new
    post 'logout'
    @controller_bak.instance_variable_set(:@session, @controller.instance_variable_get(:@session) )
    @controller = @controller_bak
  end
  
  def session
    @controller.instance_eval { @session }
  end
  
  def err(obj)
    obj.errors.each do |er,msg|
      puts "[#{er}] #{msg}"
    end
  end
  
  def method_missing(meth,*args, &block)
    @controller.send(meth, *args, &block)
  end
end
