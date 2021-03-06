%%% ====================================================================
%%% ``The contents of this file are subject to the Erlang Public License,
%%% Version 1.1, (the "License"); you may not use this file except in
%%% compliance with the License. You should have received a copy of the
%%% Erlang Public License along with this software. If not, it can be
%%% retrieved via the world wide web at http://www.erlang.org/.
%%%
%%% Software distributed under the License is distributed on an "AS IS"
%%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%%% the License for the specific language governing rights and limitations
%%% under the License.
%%%
%%% The Initial Developer of the Original Code is ProcessOne.
%%% Portions created by ProcessOne are Copyright 2006-2009, ProcessOne
%%% All Rights Reserved.''
%%% This software is copyright 2006-2009, ProcessOne.
%%%
%%% @author Pablo Polvorin <pablo.polvorin@process-one.net>
%%% @version {@vsn}, {@date} {@time}
%%% @end
%%% ====================================================================
-module(pubsub_db_odbc).
-author("pablo.polvorin@process-one.net").

-include("pubsub.hrl").

-export([add_subscription/1,
	 read_subscription/1, 
	 delete_subscription/1, 
	 update_subscription/1]).


%% TODO: Those -spec lines produce errors in old Erlang versions.
%% They can be enabled again in ejabberd 3.0 because it uses R12B or higher.
%% -spec read_subscription(SubID :: string()) -> {ok, #pubsub_subscription{}} |  notfound.
read_subscription(SubID) ->
	case ejabberd_odbc:sql_query_t(
		["select opt_name, opt_value "
		"from pubsub_subscription_opt "
		"where subid = '", ejabberd_odbc:escape(SubID), "'"]) of
		{selected, ["opt_name", "opt_value"], []} -> 
			notfound;
			
		{selected, ["opt_name", "opt_value"], Options} ->

			{ok, #pubsub_subscription{subid = SubID,
					options = lists:map(fun subscription_opt_from_odbc/1, Options)}}
	end.



%% -spec delete_subscription(SubID :: string()) -> ok.
delete_subscription(SubID) ->
	ejabberd_odbc:sql_query_t(["delete from pubsub_subscription_opt "
	"where subid = '", ejabberd_odbc:escape(SubID), "'"]),
	ok.



%% -spec update_subscription(#pubsub_subscription{}) -> ok .
update_subscription(#pubsub_subscription{subid = SubId} = Sub) -> 
	delete_subscription(SubId),
	add_subscription(Sub).

%% -spec add_subscription(#pubsub_subscription{}) -> ok.
add_subscription(#pubsub_subscription{subid = SubId, options = Opts}) ->
	EscapedSubId = ejabberd_odbc:escape(SubId),
	lists:foreach(fun(Opt) ->
		{OdbcOptName, OdbcOptValue} = subscription_opt_to_odbc(Opt),
		ejabberd_odbc:sql_query_t(
		["insert into pubsub_subscription_opt(subid, opt_name, opt_value)"
		"values ('", EscapedSubId, "','", OdbcOptName, "','", OdbcOptValue, "')"])
		end, Opts),
	ok.



%% -------------- Internal utilities -----------------------
subscription_opt_from_odbc({"DELIVER", Value}) ->
	{deliver, odbc_to_boolean(Value)};
subscription_opt_from_odbc({"DIGEST", Value}) ->
	{digest, odbc_to_boolean(Value)};
subscription_opt_from_odbc({"DIGEST_FREQUENCY", Value}) ->
	{digest_frequency, odbc_to_integer(Value)};
subscription_opt_from_odbc({"EXPIRE", Value}) ->
	{expire, odbc_to_timestamp(Value)};
subscription_opt_from_odbc({"INCLUDE_BODY", Value}) ->
	{include_body, odbc_to_boolean(Value)};

%%TODO: might be > than 1 show_values value??.
%%      need to use compact all in only 1 opt.
subscription_opt_from_odbc({"SHOW_VALUES", Value}) ->
	{show_values, Value};
subscription_opt_from_odbc({"SUBSCRIPTION_TYPE", Value}) ->
	{subscription_type, case Value of
		"items" -> items;
		"nodes" -> nodes
	end};

subscription_opt_from_odbc({"SUBSCRIPTION_DEPTH", Value}) ->
	{subscription_depth, case Value of
		"all" -> all;
		N -> odbc_to_integer(N)
	end}.

subscription_opt_to_odbc({deliver, Bool}) ->
	{"DELIVER", boolean_to_odbc(Bool)};
subscription_opt_to_odbc({digest, Bool}) ->
	{"DIGEST", boolean_to_odbc(Bool)};
subscription_opt_to_odbc({digest_frequency, Int}) ->
	{"DIGEST_FREQUENCY", integer_to_odbc(Int)};
subscription_opt_to_odbc({expire, Timestamp}) ->
	{"EXPIRE", timestamp_to_odbc(Timestamp)};
subscription_opt_to_odbc({include_body, Bool}) ->
	{"INCLUDE_BODY", boolean_to_odbc(Bool)};
subscription_opt_to_odbc({show_values, Values}) ->
	{"SHOW_VALUES", Values};
subscription_opt_to_odbc({subscription_type, Type}) ->
	{"SUBSCRIPTION_TYPE", case Type of
				items -> "items";
				nodes -> "nodes"
			       end};
subscription_opt_to_odbc({subscription_depth, Depth}) ->
	{"SUBSCRIPTION_DEPTH", case Depth of
				   all -> "all";
				   N -> integer_to_odbc(N)
				end}.

integer_to_odbc(N) ->
	integer_to_list(N).

boolean_to_odbc(true) -> "1";
boolean_to_odbc(false) -> "0".
timestamp_to_odbc(T) -> jlib:now_to_utc_string(T).


odbc_to_integer(N) -> list_to_integer(N).
odbc_to_boolean(B) -> B == "1".
odbc_to_timestamp(T) -> jlib:datetime_string_to_timestamp(T).
