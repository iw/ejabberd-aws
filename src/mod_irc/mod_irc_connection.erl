%%%----------------------------------------------------------------------
%%% File    : mod_irc_connection.erl
%%% Author  : Alexey Shchepin <alexey@sevcom.net>
%%% Purpose : 
%%% Created : 15 Feb 2003 by Alexey Shchepin <alexey@sevcom.net>
%%% Id      : $Id$
%%%----------------------------------------------------------------------

-module(mod_irc_connection).
-author('alexey@sevcom.net').
-vsn('$Revision$ ').

-behaviour(gen_fsm).

%% External exports
-export([start/3, receiver/2, route/4]).

%% gen_fsm callbacks
-export([init/1,
	 open_socket/2,
	 %wait_for_registration/2,
	 stream_established/2,
	 handle_event/3,
	 handle_sync_event/4,
	 handle_info/3,
	 terminate/3,
	 code_change/4]).

-include("ejabberd.hrl").
-include("namespaces.hrl").

-record(state, {socket, receiver, queue,
		user, myname, server, nick,
		inbuf = "", outbuf = ""}).

-define(IRC_ENCODING, "koi8-r").

-define(DBGFSM, true).

-ifdef(DBGFSM).
-define(FSMOPTS, [{debug, [trace]}]).
-else.
-define(FSMOPTS, []).
-endif.

%%%----------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------
start(From, Host, Server) ->
    gen_fsm:start(?MODULE, [From, Host, Server], ?FSMOPTS).

%%%----------------------------------------------------------------------
%%% Callback functions from gen_fsm
%%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%% Func: init/1
%% Returns: {ok, StateName, StateData}          |
%%          {ok, StateName, StateData, Timeout} |
%%          ignore                              |
%%          {stop, StopReason}                   
%%----------------------------------------------------------------------
init([From, Host, Server]) ->
    gen_fsm:send_event(self(), init),
    {Nick, _, _} = From,
    {ok, open_socket, #state{queue = queue:new(),
			     user = From,
			     nick = Nick,
			     myname = Host,
			     server = Server}}.

%%----------------------------------------------------------------------
%% Func: StateName/2
%% Returns: {next_state, NextStateName, NextStateData}          |
%%          {next_state, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}                         
%%----------------------------------------------------------------------
open_socket(init, StateData) ->
    Addr = StateData#state.server,
    Port = 6667,
    ?DEBUG("connecting to ~s:~p~n", [Addr, Port]),
    case gen_tcp:connect(Addr, Port, [binary, {packet, 0}]) of
	{ok, Socket} ->
	    % TODO: send nick, etc...
	    %send_text(Socket, io_lib:format(?STREAM_HEADER,
	    %    			    [StateData#state.server])),
	    %send_queue(StateData#state.socket, StateData#state.queue),
	    send_text(Socket, io_lib:format("NICK ~s\r\n",
					    [StateData#state.nick])),
	    send_text(Socket,
		      io_lib:format(
			"USER ~s ~s ~s :~s\r\n",
			[StateData#state.nick,
			 StateData#state.nick,
			 StateData#state.myname,
			 StateData#state.nick])),
	    {next_state, wait_for_registration,
	     StateData#state{socket = Socket}};
	{error, Reason} ->
	    ?DEBUG("connect return ~p~n", [Reason]),
	    Text = case Reason of
		       timeout -> "Server Connect Timeout";
		       _ -> "Server Connect Failed"
		   end,
	    bounce_messages(Text),
	    {stop, normal, StateData}
    end.


stream_established({xmlstreamend, Name}, StateData) ->
    {stop, normal, StateData};

stream_established(timeout, StateData) ->
    {stop, normal, StateData};

stream_established(closed, StateData) ->
    {stop, normal, StateData}.



%%----------------------------------------------------------------------
%% Func: StateName/3
%% Returns: {next_state, NextStateName, NextStateData}            |
%%          {next_state, NextStateName, NextStateData, Timeout}   |
%%          {reply, Reply, NextStateName, NextStateData}          |
%%          {reply, Reply, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}                          |
%%          {stop, Reason, Reply, NewStateData}                    
%%----------------------------------------------------------------------
%state_name(Event, From, StateData) ->
%    Reply = ok,
%    {reply, Reply, state_name, StateData}.

%%----------------------------------------------------------------------
%% Func: handle_event/3
%% Returns: {next_state, NextStateName, NextStateData}          |
%%          {next_state, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}                         
%%----------------------------------------------------------------------
handle_event(Event, StateName, StateData) ->
    {next_state, StateName, StateData}.

%%----------------------------------------------------------------------
%% Func: handle_sync_event/4
%% Returns: {next_state, NextStateName, NextStateData}            |
%%          {next_state, NextStateName, NextStateData, Timeout}   |
%%          {reply, Reply, NextStateName, NextStateData}          |
%%          {reply, Reply, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}                          |
%%          {stop, Reason, Reply, NewStateData}                    
%%----------------------------------------------------------------------
handle_sync_event(Event, From, StateName, StateData) ->
    Reply = ok,
    {reply, Reply, StateName, StateData}.

code_change(OldVsn, StateName, StateData, Extra) ->
    {ok, StateName, StateData}.

-define(SEND(S),
	if
	    StateName == stream_established ->
		send_text(StateData#state.socket, S),
		StateData;
	    true ->
		StateData#state{outbuf = StateData#state.outbuf ++ S}
	end).

%%----------------------------------------------------------------------
%% Func: handle_info/3
%% Returns: {next_state, NextStateName, NextStateData}          |
%%          {next_state, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}                         
%%----------------------------------------------------------------------
handle_info({route, Channel, Resource, {xmlelement, "presence", Attrs, Els}},
	    StateName, StateData) ->
    NewStateData =
	case xml:get_attr_s("type", Attrs) of
	    "unavailable" ->
		?SEND(io_lib:format("PART #~s\r\n", [Channel]));
	    "subscribe" -> StateData;
	    "subscribed" -> StateData;
	    "unsubscribe" -> StateData;
	    "unsubscribed" -> StateData;
	    _ ->
		?SEND(io_lib:format("JOIN #~s\r\n", [Channel]))
	end,
    {next_state, StateName, NewStateData};

handle_info({route, Channel, Resource,
	     {xmlelement, "message", Attrs, Els} = El},
	    StateName, StateData) ->
    NewStateData =
	case xml:get_attr_s("type", Attrs) of
	    "groupchat" ->
		ejabberd_router:route(
		  {lists:concat([Channel, "%", StateData#state.server]),
		   StateData#state.myname, StateData#state.nick},
		  StateData#state.user, El),
		% TODO: remove newlines from body
		Body = xml:get_path_s(El, [{elem, "body"}, cdata]),
		?SEND(io_lib:format("PRIVMSG #~s :~s\r\n", [Channel, Body]));
	    _ -> StateData
	end,
    {next_state, StateName, NewStateData};

handle_info({route, Channel, Resource, Packet}, StateName, StateData) ->
    {next_state, StateName, StateData};


handle_info({ircstring, [$P, $I, $N, $G, $  | ID]}, StateName, StateData) ->
    send_text(StateData#state.socket, "PONG " ++ ID ++ "\r\n"),
    {next_state, StateName, StateData};

handle_info({ircstring, [$: | String]}, StateName, StateData) ->
    Words = string:tokens(String, " "),
    case Words of
	[_, "353" | Items] ->
	    process_channel_list(StateData, Items);
	[From, "PRIVMSG", [$# | Chan] | _] ->
	    process_privmsg(StateData, Chan, From, String);
	[From, "PART", [$# | Chan] | _] ->
	    process_part(StateData, Chan, From, String);
	[From, "JOIN", Chan | _] ->
	    process_join(StateData, Chan, From, String);
	[From, "MODE", [$# | Chan], "+o", Nick | _] ->
	    process_mode_o(StateData, Chan, From, Nick,
			   "admin", "moderator");
	[From, "MODE", [$# | Chan], "-o", Nick | _] ->
	    process_mode_o(StateData, Chan, From, Nick,
			   "member", "participant");
	_ ->
	    io:format("unknown irc command '~s'~n", [String])
    end,
    NewStateData =
	case StateData#state.outbuf of
	    "" ->
		StateData;
	    Data ->
		send_text(StateData#state.socket, Data),
		StateData#state{outbuf = ""}
	end,
    {next_state, stream_established, NewStateData};


handle_info({ircstring, String}, StateName, StateData) ->
    io:format("unknown irc command '~s'~n", [String]),
    {next_state, StateName, StateData};


handle_info({send_text, Text}, StateName, StateData) ->
    send_text(StateData#state.socket, Text),
    {next_state, StateName, StateData};
handle_info({send_element, El}, StateName, StateData) ->
    case StateName of
	stream_established ->
	    send_element(StateData#state.socket, El),
	    {next_state, StateName, StateData};
	_ ->
	    Q = queue:in(El, StateData#state.queue),
	    {next_state, StateName, StateData#state{queue = Q}}
    end;
handle_info({tcp, Socket, Data}, StateName, StateData) ->
    Buf = StateData#state.inbuf ++ binary_to_list(Data),
    {ok, Strings} = regexp:split(Buf, "\r\n"),
    io:format("strings=~p~n", [Strings]),
    NewBuf = process_lines(Strings),
    {next_state, StateName, StateData#state{inbuf = NewBuf}};
handle_info({tcp_closed, Socket}, StateName, StateData) ->
    gen_fsm:send_event(self(), closed),
    {next_state, StateName, StateData};
handle_info({tcp_error, Socket, Reason}, StateName, StateData) ->
    gen_fsm:send_event(self(), closed),
    {next_state, StateName, StateData}.

%%----------------------------------------------------------------------
%% Func: terminate/3
%% Purpose: Shutdown the fsm
%% Returns: any
%%----------------------------------------------------------------------
terminate(Reason, StateName, StateData) ->
    ejabberd_mod_irc ! {closed_conection, {StateData#state.user,
					   StateData#state.server}},
    case StateData#state.socket of
	undefined ->
	    ok;
	Socket ->
	    gen_tcp:close(Socket)
    end,
    ok.

%%%----------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------

receiver(Socket, C2SPid) ->
    XMLStreamPid = xml_stream:start(C2SPid),
    receiver(Socket, C2SPid, XMLStreamPid).

receiver(Socket, C2SPid, XMLStreamPid) ->
    case gen_tcp:recv(Socket, 0) of
        {ok, Text} ->
	    xml_stream:send_text(XMLStreamPid, Text),
	    receiver(Socket, C2SPid, XMLStreamPid);
        {error, Reason} ->
	    exit(XMLStreamPid, closed),
	    gen_fsm:send_event(C2SPid, closed),
	    ok
    end.

send_text(Socket, Text) ->
    CText = iconv:convert("utf-8", ?IRC_ENCODING, lists:flatten(Text)),
    %io:format("IRC OUTu: ~s~nIRC OUTk: ~s~n", [Text, CText]),
    gen_tcp:send(Socket, CText).

send_element(Socket, El) ->
    send_text(Socket, xml:element_to_string(El)).

send_queue(Socket, Q) ->
    case queue:out(Q) of
	{{value, El}, Q1} ->
	    send_element(Socket, El),
	    send_queue(Socket, Q1);
	{empty, Q1} ->
	    ok
    end.

bounce_messages(Reason) ->
    receive
	{send_element, El} ->
	    {xmlelement, Name, Attrs, SubTags} = El,
	    case xml:get_attr_s("type", Attrs) of
	        "error" ->
	            ok;
	        _ ->
	            Err = jlib:make_error_reply(El,
	        				"502", Reason),
		    From = jlib:string_to_jid(xml:get_attr_s("from", Attrs)),
		    To = jlib:string_to_jid(xml:get_attr_s("to", Attrs)),
		    ejabberd_router ! {route, To, From, Err}
	    end,
	    bounce_messages(Reason)
    after 0 ->
	    ok
    end.


route(Pid, Channel, Resource, Packet) ->
    Pid ! {route, Channel, Resource, Packet}.


process_lines([S]) ->
    S;
process_lines([S | Ss]) ->
    self() ! {ircstring, iconv:convert(?IRC_ENCODING, "utf-8", S)},
    process_lines(Ss).

process_channel_list(StateData, Items) ->
    process_channel_list_find_chan(StateData, Items).

process_channel_list_find_chan(StateData, []) ->
    ok;
process_channel_list_find_chan(StateData, [[$# | Chan] | Items]) ->
    process_channel_list_users(StateData, Chan, Items);
process_channel_list_find_chan(StateData, [_ | Items]) ->
    process_channel_list_find_chan(StateData, Items).

process_channel_list_users(StateData, Chan, []) ->
    ok;
process_channel_list_users(StateData, Chan, [User | Items]) ->
    process_channel_list_user(StateData, Chan, User),
    process_channel_list_users(StateData, Chan, Items).

process_channel_list_user(StateData, Chan, User) ->
    User1 = case User of
		[$: | U1] -> U1;
		_ -> User
	    end,
    {User2, Affiliation, Role} =
	case User1 of
	    [$@ | U2] -> {U2, "admin", "moderator"};
	    _ -> {User1, "member", "participant"}
	end,
    ejabberd_router:route({lists:concat([Chan, "%", StateData#state.server]),
			   StateData#state.myname, User2},
			  StateData#state.user,
			  {xmlelement, "presence", [],
			   [{xmlelement, "x", [{"xmlns", ?NS_MUC_USER}],
			     [{xmlelement, "item",
			       [{"affiliation", Affiliation},
				{"role", Role}],
			       []}]}]}).


process_privmsg(StateData, Chan, From, String) ->
    [FromUser | _] = string:tokens(From, "!"),
    Msg = lists:last(string:tokens(String, ":")),
    ejabberd_router:route({lists:concat([Chan, "%", StateData#state.server]),
			   StateData#state.myname, FromUser},
			  StateData#state.user,
			  {xmlelement, "message", [{"type", "groupchat"}],
			   [{xmlelement, "body", [], [{xmlcdata, Msg}]}]}).

process_part(StateData, Chan, From, String) ->
    [FromUser | _] = string:tokens(From, "!"),
    %Msg = lists:last(string:tokens(String, ":")),
    ejabberd_router:route({lists:concat([Chan, "%", StateData#state.server]),
			   StateData#state.myname, FromUser},
			  StateData#state.user,
			  {xmlelement, "presence", [{"type", "unavailable"}],
			   [{xmlelement, "x", [{"xmlns", ?NS_MUC_USER}],
			     [{xmlelement, "item",
			       [{"affiliation", "member"},
				{"role", "none"}],
			       []}]}]}).


process_join(StateData, Channel, From, String) ->
    [FromUser | _] = string:tokens(From, "!"),
    Chan = lists:subtract(Channel, ":#"),
    ejabberd_router:route({lists:concat([Chan, "%", StateData#state.server]),
			   StateData#state.myname, FromUser},
			  StateData#state.user,
			  {xmlelement, "presence", [],
			   [{xmlelement, "x", [{"xmlns", ?NS_MUC_USER}],
			     [{xmlelement, "item",
			       [{"affiliation", "member"},
				{"role", "participant"}],
			       []}]}]}).


process_mode_o(StateData, Chan, From, Nick, Affiliation, Role) ->
    %Msg = lists:last(string:tokens(String, ":")),
    ejabberd_router:route({lists:concat([Chan, "%", StateData#state.server]),
			   StateData#state.myname, Nick},
			  StateData#state.user,
			  {xmlelement, "presence", [],
			   [{xmlelement, "x", [{"xmlns", ?NS_MUC_USER}],
			     [{xmlelement, "item",
			       [{"affiliation", Affiliation},
				{"role", Role}],
			       []}]}]}).


