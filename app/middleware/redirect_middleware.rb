class RedirectMiddleware
    def initialize(app)
      @app = app
    end
  
    def call(env)
      if !Rails.env.development? && env['PATH_INFO'] == '/script.js'
        return redirect("#{ENV.fetch("SCRIPT_JS_URL", nil)}", 302)
      end
      @app.call(env)
    end
  
    def redirect(location, status)
      body = "<html><body>You are being <a href=\"#{location}\">redirected</a>.</body></html>"
      [status, {"Location" => location, "Content-Type" => "text/html"}, [body]]
    end
  end