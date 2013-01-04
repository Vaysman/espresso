module ECoreTest__Rewriter

  class Cms < E
    map '/'

    def articles *args
      raise 'this action should never be executed'
    end

    def old_news *args
      raise 'this action should never be executed'
    end

    def old_pages *args
      raise 'this action should never be executed'
    end

    def test_pass *args
      [args, params].flatten.inspect
    end

    def news name
      [name, params].inspect
    end

    def page
      params.inspect
    end
  end

  class Store < E
    map '/'

    def buy product
      [product, params]
    end
  end
  Store.mount

  Spec.new self do

    eapp = EApp.new do

      mount Cms

      rewrite /\A\/articles\/(\d+)\.html$/ do |title|
        redirect '/page?title=%s' % title
      end

      rewrite /\A\/landing\-page\/([\w|\d]+)\/([\w|\d]+)/ do |page, product|
        redirect Store.route(:buy, product, :page => page)
      end

      rewrite /\A\/News\/(.*)\.php/ do |name|
        redirect Cms.route(:news, name, (request.query_string.size > 0 ? '?' << request.query_string : ''))
      end

      rewrite /\A\/old_news\/(.*)\.php/ do |name|
        permanent_redirect Cms.route(:news, name)
      end

      rewrite /\A\/pages\/+([\w|\d]+)\-(\d+)\.html/i do |name, id|
        redirect Cms.route(:page, name, :id => id)
      end

      rewrite /\A\/old_pages\/+([\w|\d]+)\-(\d+)\.html/i do |name, id|
        permanent_redirect "/page?name=#{ name }&id=#{ id }"
      end

      rewrite /\A\/pass_test_I\/(.*)/ do |name|
        pass Cms, :test_pass, name, :name => name
      end

      rewrite /\A\/pass_test_II\/(.*)/ do |name|
        pass Store, :buy, name, :name => name
      end

      rewrite /\A\/halt_test_I\/(.*)\/(\d+)/ do |body, code|
        halt body, code.to_i, 'TEST' => '%s|%s' % [body, code]
        raise 'this shit should not be happen'
      end

      rewrite /\A\/halt_test_II\/(.*)\/(\d+)/ do |body, code|
        halt [code.to_i, {'TEST' => '%s|%s' % [body, code]}, body]
        raise 'this shit should not be happen'
      end

      rewrite /\/context_sensitive\/(.*)/ do |name|
        if request.user_agent =~ /google/
          permanent_redirect Cms.route(:news, name)
        else
          redirect Cms.route(:news, name)
        end
      end
    end
    app eapp

    def redirected? response, status = 302
      check(response.status) == status
    end

    def check_redir_location(location, status=302)
      is_redirect?(status)
      is_location? location
    end

    testing :redirect do
      page, product = rand(1000000).to_s, rand(1000000).to_s
      get '/landing-page/%s/%s' % [page, product]
      check_redir_location(Store.route(:buy, product, :page => page))

      var = rand 1000000
      get '/articles/%s.html' % var
      check_redir_location('/page?title=%s' % var)

      var = rand.to_s
      get '/News/%s.php' % var
      check_redir_location('/news/%s/' % var)

      var, val = rand.to_s, rand.to_s
      get '/News/%s.php' % var, var => val
      check_redir_location('/news/%s/?%s=%s' % [var, var, val])

      var = rand.to_s
      get '/old_news/%s.php' % var
      check_redir_location('/news/%s' % var, 301)

      name, id = rand(1000000), rand(100000)
      get '/pages/%s-%s.html' % [name, id]
      check_redir_location('/page/%s?id=%s' % [name, id])

      name, id = rand(1000000), rand(100000)
      get '/old_pages/%s-%s.html' % [name, id]
      check_redir_location('/page?name=%s&id=%s' % [name, id], 301)
    end

    testing :pass do
      name = rand(100000).to_s
      response = get '/pass_test_I/%s' % name
      if RUBY_VERSION.to_f > 1.8
        is_ok_body? [name, {'name' => name}].inspect
      else
        #returns 404 cause splat params does not work on E running on ruby1.8' do
        is_not_found?
        is_body? 'max params accepted: 0; params given: 1'
      end

      name = rand(100000).to_s
      response = get '/pass_test_II/%s' % name
      is_ok_body? [name, {'name' => name}].to_s
    end

    testing :halt do
      def check_result(code, body)
        is_status? code
        is_body? body
        is_header? 'TEST', '%s|%s' % [body, code]
      end

      body, code = rand(100000).to_s, 500
      response = get '/halt_test_I/%s/%s' % [body, code]
      check_result(code, body)

      body, code = rand(100000).to_s, 500
      response = get '/halt_test_II/%s/%s' % [body, code]
      check_result(code, body)
    end

    testing :context do
      name = rand(100000).to_s
      get '/context_sensitive/%s' % name
      is_redirect?
      follow_redirect!
      is_ok_body? [name, {}].inspect

      header['User-Agent'] = 'google'
      get '/context_sensitive/%s' % name
      is_redirect? 301
      follow_redirect!
      is_ok_body? [name, {}].inspect
    end
  end
end
