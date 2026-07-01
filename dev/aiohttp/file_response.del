// file_response.c3

// File response support for ext::aio::http

// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

import ext::aio;

fn Response*? response_file(String path)
{
    if (path.len == 0) return BAD_REQUEST~;

    Response* res = response_empty(200)!;

    res.body_kind = BODY_FILE;
    res.file_path = path.copy(localmem);
    res.own_file_path = true;

    res.header("Transfer-Encoding", "chunked")!;
    res.header("Content-Type", content_type_from_path(path))!;

    return res;
}

fn Response*? Context.file(&self, String path)
{
    Response* res = response_file(path)!;

    self.with_response(res)!;

    return self.res;
}