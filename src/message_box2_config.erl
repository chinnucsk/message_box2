%% File : message_box_config.erl
%% Description : configuration manager for message_box

-module(message_box2_config).
-include_lib("eunit/include/eunit.hrl").
-export([load/0, load/1, get/1]).

load() ->
    {ThisFile, _} = filename:find_src(message_box2_config),
    SrcDir = filename:dirname(ThisFile),
    ConfFilePath = filename:absname_join(SrcDir, "../conf/message_box2.conf"),
    load(ConfFilePath).

load(File) ->
    case file:open(File, read) of
	{ok, Dev} ->
	    {ok, {config, ConfigList}} = io:read(Dev, 0),
	    read_config(message_box2, ConfigList),
	    file:close(Dev);
	Other ->
	    ?debugVal(Other),
	    Other
    end.

read_config(AppName, ConfigList) ->
    case ConfigList of
	[] -> ok;
	[Config | Tail] ->
	    {Key, Val} = Config,
	    application:set_env(AppName, Key, Val),
	    read_config(AppName, Tail)
    end.

get(Name) ->
    {ok, Value} = application:get_env(message_box2, Name),
    Value.
