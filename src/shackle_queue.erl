-module(shackle_queue).
-include("shackle_internal.hrl").

-compile(inline).
-compile({inline_size, 512}).

%% internal
-export([
    add/2,
    clear/1,
    init/0,
    remove/1,
    remove/2
]).

%% internal
-spec add(external_request_id(), cast()) ->
    ok.

add(ExtRequestId, #cast {
        request_id = {ServerName, _} = RequestId
    } = Cast) ->

    Object = {{ServerName, ExtRequestId}, Cast},
    ets:insert(?ETS_TABLE_QUEUE, Object),

    Object2 = {RequestId, ExtRequestId},
    ets:insert(?ETS_TABLE_QUEUE_REVERSE, Object2),

    ok.

-spec clear(server_name()) ->
    [cast()].

clear(ServerName) ->
    Match = {{ServerName, '_'}, '_'},
    case ets_match_take(?ETS_TABLE_QUEUE, Match) of
        [] ->
            [];
        Objects ->
            ets:match_delete(?ETS_TABLE_QUEUE_REVERSE, Match),
            [Cast || {_, Cast} <- Objects]
    end.

-spec init() ->
    ok.

init() ->
    ets_new(?ETS_TABLE_QUEUE),
    ets_new(?ETS_TABLE_QUEUE_REVERSE),
    ok.

-spec remove(request_id()) ->
    {ok, cast()} | {error, not_found}.

remove({ServerName, _} = RequestId) ->
    case ets_take(?ETS_TABLE_QUEUE_REVERSE, RequestId) of
        [] ->
            {error, not_found};
        [{_, ExtRequestId}] ->
            case ets_take(?ETS_TABLE_QUEUE, {ServerName, ExtRequestId}) of
                [] ->
                    {error, not_found};
                [{_, Cast}] ->
                    {ok, Cast}
            end
    end.

-spec remove(server_name(), external_request_id()) ->
    {ok, cast()} | {error, not_found}.

remove(ServerName, ExtRequestId) ->
    case ets_take(?ETS_TABLE_QUEUE, {ServerName, ExtRequestId}) of
        [] ->
            {error, not_found};
        [{_, #cast {request_id = RequestId} = Cast}] ->
            ets:delete(?ETS_TABLE_QUEUE_REVERSE, RequestId),
            {ok, Cast}
    end.

%% private
ets_match_take(Tid, Match) ->
    case ets:match_object(Tid, Match) of
        [] ->
            [];
        Objects ->
            ets:match_delete(Tid, Match),
            Objects
    end.

ets_new(Tid) ->
    ets:new(Tid, [
        named_table,
        public,
        {read_concurrency, true},
        {write_concurrency, true}
    ]).

-ifdef(ETS_TAKE).

ets_take(Tid, Key) ->
    ets:take(Tid, Key).

-else.

ets_take(Tid, Key) ->
    case ets:lookup(Tid, Key) of
        [] ->
            [];
        Objects ->
            ets:delete(Tid, Key),
            Objects
    end.

-endif.
