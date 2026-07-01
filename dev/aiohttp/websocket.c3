// websocket.c3

// High-level WebSocket callback API.
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

import c::errno;

// Handler

alias WebSocketHandler = fn void?(WebSocketConnection*, WebSocketMessage*);


// Run loop

fn void? WebSocketConnection.run(&self, WebSocketHandler handler)
{
    if (handler == null) return errno::E_INVALID_ARG~;

    while (self.is_open()) {
        WebSocketMessage? result = self.receive();

        if (catch err = result) {
            if (err == WS_CONNECTION_CLOSED || err == WS_CONNECTION_TRUNCATED) {
                return;
            }

            if (err == WS_MESSAGE_TOO_LARGE) {
                if (self.is_open() && !self.close_sent) {
                    self.send_close(WS_CLOSE_MESSAGE_TOO_BIG, "Message too large")!!;
                }

                self.abort();
                return err~;
            }

            if (err == WS_INVALID_UTF8) {
                if (self.is_open() && !self.close_sent) {
                    self.send_close(WS_CLOSE_INVALID_PAYLOAD, "Invalid UTF-8")!!;
                }

                self.abort();
                return err~;
            }

            if (err == WS_FRAME_INVALID ||
                err == WS_FRAME_INVALID_OPCODE ||
                err == WS_FRAME_INVALID_CONTROL ||
                err == WS_FRAME_NOT_MASKED ||
                err == WS_FRAME_UNEXPECTED_MASK ||
                err == WS_CLOSE_INVALID) {
                if (self.is_open() && !self.close_sent) {
                    self.send_close(WS_CLOSE_PROTOCOL_ERROR, "Protocol error")!!;
                }

                self.abort();
                return err~;
            }

            self.abort();
            return err~;
        }

        WebSocketMessage message = result;
        defer message.free();

        handler(self, &message)!;
    }
}


// Common handlers

fn void? websocket_echo_handler(WebSocketConnection* connection, WebSocketMessage* message)
{
    if (connection == null || message == null) return errno::E_INVALID_ARG~;

    if (message.is_text()) {
        connection.send_text(message.text())!;
        return;
    }

    if (message.is_binary()) {
        connection.send_binary(message.data)!;
    }
}


// Server helper

fn void? websocket_run_server(aio::Stream* stream, WebSocketHandler handler, ulong read_timeout_us = WS_DEFAULT_READ_TIMEOUT_US)
{
    if (stream == null || handler == null) return errno::E_INVALID_ARG~;

    WebSocketConnection* connection = ws_connection_new(stream, true)!;
    defer ws_connection_free(connection);

    connection.set_read_timeout_us(read_timeout_us);
    connection.run(handler)!;
}


// Client helper

fn void? websocket_run_client(aio::Stream* stream, WebSocketHandler handler, ulong read_timeout_us = WS_DEFAULT_READ_TIMEOUT_US)
{
    if (stream == null || handler == null) return errno::E_INVALID_ARG~;

    WebSocketConnection* connection = ws_connection_new(stream, false)!;
    defer ws_connection_free(connection);

    connection.set_read_timeout_us(read_timeout_us);
    connection.run(handler)!;
}

// eof