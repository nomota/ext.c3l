import ext::aio;
import ext::aio::http;

fn http::Response*? show_user(http::Ctx* c) // handler
{
    String id = c.param("id")!; // get path param, e.g. /users/23 => id = 23
    return c.text(id)!; // simple text response
}

fn void? app_task(void* arg)
{
    http::Application app; // main app
    app.init();
    defer app.deinit();

    http::Application api; // api sub-part
    api.init();
    defer api.deinit();
    
    //api.get("/users", &list_users)!; // register GET handler to api subpart i.e. "/api-v2/users"
    api.get("/users/:id", &show_user)!; // register GET handler to api subpart i.e. "/api-v2/users/:id"
    
    app.mount("/api-v2", &api)!; // register a route api subpart to the main app
    
    app.serve("127.0.0.1", 8080)!;
}

fn void main()
{
    aio::run(&app_task)!!;
}

/* 
GET /api-v2/users/34 HTTP/1.0
*/