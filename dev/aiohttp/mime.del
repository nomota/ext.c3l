// mime.c3

// MIME type helpers for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

fn String content_type_from_path(String path)
{
    if (str_ends_with(path, ".html") || str_ends_with(path, ".htm"))
    {
        return "text/html; charset=utf-8";
    }

    if (str_ends_with(path, ".txt"))
    {
        return "text/plain; charset=utf-8";
    }

    if (str_ends_with(path, ".css"))
    {
        return "text/css; charset=utf-8";
    }

    if (str_ends_with(path, ".js"))
    {
        return "application/javascript; charset=utf-8";
    }

    if (str_ends_with(path, ".json"))
    {
        return "application/json; charset=utf-8";
    }

    if (str_ends_with(path, ".png"))
    {
        return "image/png";
    }

    if (str_ends_with(path, ".jpg") || str_ends_with(path, ".jpeg"))
    {
        return "image/jpeg";
    }

    if (str_ends_with(path, ".gif"))
    {
        return "image/gif";
    }

    if (str_ends_with(path, ".svg"))
    {
        return "image/svg+xml";
    }

    if (str_ends_with(path, ".wasm"))
    {
        return "application/wasm";
    }

    return "application/octet-stream";
}