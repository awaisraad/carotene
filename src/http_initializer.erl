-module(http_initializer).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, terminate/2, handle_info/2, code_change/3]).

-record(state, {transport, supervisor}).

start_link(Sup) ->
    Opts = [],
    gen_server:start(?MODULE, [Sup], Opts).

init([Sup]) ->
    self() ! {start_transport, Sup},
    {ok, #state{supervisor = Sup}}.

handle_call(alloc, _From, State) ->
    {reply, normal, ok, State}.

handle_cast(_Message, State) ->
    {noreply, State}.

handle_info({start_transport, Sup}, State = #state{supervisor = Sup}) ->
    %TODO: monitor transport instead of making it permanent so we update the ref
    {ok, _} = supervisor:start_child(Sup, {transport,
         {transport_sup, start_link, []},
          permanent,
          infinity,
          worker,
          [transport_sup]}),

    Transport = transport_sup:get_transport(),

    Dispatch = cowboy_router:compile([
        {'_', [
            {"/websocket", ws_handler, [Transport]}
        ]}
    ]),
    {ok, _} = cowboy:start_http(http, 1, [{port, 8080}],
        [{env, [{dispatch, Dispatch}]}]),
    io:format("~s~n", ["Server started at port 8080"]),
    {noreply, State#state{transport = Transport}};
handle_info(shutdown, State) ->
    {noreply, State}.

terminate(_Reason, State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

