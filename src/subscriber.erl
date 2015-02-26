-module(subscriber).

-behaviour(gen_server).

-export([init/1, terminate/2, code_change/3, handle_call/3,
         handle_cast/2, handle_info/2]).
-export([start/3, start_link/3]).
-export([stop/1]).

-record(state, {channel, reply_pid, already_authorized, user_id}).

start_link(Channel, UserId, ReplyPid) ->
    Opts = [],
    gen_server:start_link(?MODULE, [Channel, UserId, ReplyPid], Opts).

start(Channel, UserId, ReplyPid) ->
    Opts = [],
    gen_server:start(?MODULE, [Channel, UserId, ReplyPid], Opts).

stop(Pid) ->
    gen_server:call(Pid, stop, infinity).

init([Channel, UserId, ReplyPid]) ->
    erlang:monitor(process, ReplyPid),
    {ok, #state{reply_pid = ReplyPid, channel = Channel, user_id = UserId}}.

handle_info({'DOWN', _Ref, process, _Pid, _}, State) ->
    {stop, normal, State};

handle_info({received_message, Msg}, State = #state{reply_pid = ReplyPid}) ->
    ReplyPid ! {received_message, Msg},
    {noreply, State};

handle_info(shutdown, State) ->
    {stop, normal, State}.

handle_call(subscribe, _From, State = #state{channel = Channel, user_id = UserId}) ->
    Res = maybe_consume(UserId, Channel),
    {reply, Res, State};

handle_call(stop, _From, State) ->
    {stop, normal, ok, State}.

handle_cast(_Message, State) ->
    {noreply, State}.

terminate(_Reason, #state{channel = Channel, user_id = UserId}) ->
    ok = gen_server:cast(router, {unsubscribe, Channel, from, self(), user_id, UserId}).

code_change(_OldVsn, State, _Extra) ->
    State.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------

maybe_consume(UserId, Channel) ->
    case can_subscribe(UserId, Channel) of
        true -> subscribe(Channel, UserId),
                ok;
        Error -> {error, Error}
    end.

can_subscribe(UserId, Channel) ->
    case application:get_env(carotene, subscribe_authorization) of
        % if no authorization config defined, user can publish
        undefined -> true;
        {ok, AuthConfig} -> carotene_authorization:check_authorization(UserId, Channel, AuthConfig)
    end.

subscribe(Channel, UserId) ->
    ok = gen_server:cast(router, {subscribe, Channel, from, self(), user_id, UserId}).
