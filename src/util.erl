%% File : util.erl
%% Description : utilities used by other module

-module(util).
-include_lib("eunit/include/eunit.hrl").
-include("message_box.hrl").
-include("user.hrl").
-include("message.hrl").
-export([get_user_from_message_id/1, get_user_id_from_message_id/1, 
	 formatted_number/2, formatted_number/3, get_timeline_ids/4,
	 get_reply_list/1, is_reply_text/1,
	 db_info/1, sleep/1, icon_path/1,
	 get_md5_password/2, get_onetime_password/2, 
	 authenticate/2, authenticate/3,
         shurink_ets/2]).

-define(SEPARATOR, "\s\n").
-define(MD5_KEY1, "message_box2").
-define(MD5_KEY2, "garigarikunnashiaji").
-define(MD5_KEY3, "goronekogorousan").

-spec(get_user_id_from_message_id(MessageId::integer()) -> integer() ).

get_user_id_from_message_id(MessageId) ->
    IdStr = util:formatted_number(MessageId, ?MESSAGE_ID_LENGTH),
    {UserId, _Rest} = string:to_integer(string:substr(IdStr, 1, 
						      ?USER_ID_LENGTH)),
    UserId.

-spec(get_user_from_message_id(MessageId::integer()) -> #user{} ).

get_user_from_message_id(MessageId) ->
    IdStr = util:formatted_number(MessageId, ?MESSAGE_ID_LENGTH),
    {UserId, _Rest} = string:to_integer(string:substr(IdStr, 1, 
						      ?USER_ID_LENGTH)),
    message_box2_user_db:lookup_id(UserId).

formatted_number(Num, Len)->
    formatted_number(Num, Len, "0").

formatted_number(Num, Len, EmptyChar)->
    Result = integer_to_list(Num),
    ResultLen = string:len(Result),
    if 
	ResultLen > Len -> Result;
	true -> add_string(before, Len, EmptyChar, Result)
    end.

add_string(before, Len, EmptyChar, Result)->
    case string:len(Result) of
	Len -> Result;
	_Other -> 
	    NewResult = string:concat(EmptyChar, Result),
	    add_string(before, Len, EmptyChar, NewResult)
    end.
	    
-spec(get_timeline_ids(Tid::tid(), Count::integer(), 
                       Before::integer(), Result::[integer()]) -> [term()]).

get_timeline_ids(Tid, Count, Before, Result)->
    if
	length(Result) >= Count -> lists:reverse(Result);
	true -> case ets:next(Tid, Before) of
		    '$end_of_table' -> lists:reverse(Result);
		    Id -> get_timeline_ids(Tid, Count, Id, 
					   [Id | Result])
		end
    end.

%%
%% @doc create reply name list from tweet text.
%%
-spec(get_reply_list(string()) -> list(binary()) ).

get_reply_list(Text) when is_binary(Text) ->
    get_reply_list(binary_to_list(Text));

get_reply_list(Text) when is_list(Text) ->
    Tokens = string:tokens(Text, ?SEPARATOR),
    get_reply_list(Tokens, []).

get_reply_list([], List) -> lists:usort(List);

get_reply_list(Tokens, List) when is_list(Tokens) ->
    [Token | Tail] = Tokens,
    case string:sub_string(Token, 1, 1) of
	"@" ->
	    UserNameStr = string:sub_string(Token, 2, length(Token)),
	    get_reply_list(Tail, [list_to_binary(UserNameStr) | List]);
	_Other ->
	    get_reply_list(Tail, List)
    end.

%%
%% @doc if added Text is replay message.return {true, #usr{}} orelse {false, nil}
%%
-spec(is_reply_text(binary() | string()) -> {true, #user{}} | {false, nil} ).

is_reply_text(Text) when is_binary(Text) ->
    is_reply_text(binary_to_list(Text));

is_reply_text(Text) when is_list(Text) ->
    case string:sub_string(Text, 1, 1) of
	"@" ->
	    [ToToken | _Tail] = string:tokens(Text, ?SEPARATOR),
	    case string:sub_string(ToToken, 2, length(ToToken)) of
		"" -> {false, nil};
		To ->
                    case message_box2_user_db:lookup_name(To) of
                        {ok, User} ->
                            {true, User};
                        _->
                            {false, nil}
                    end
	    end;
	_Other ->
	    {false, nil}
    end.

%%
%% @doc sqlite3 database file name
%%
db_info(UserName)->
    DiscName = list_to_atom(atom_to_list(UserName) ++ "_disk"),
    FileName = atom_to_list(UserName) ++ ".db",
    DB_DIR = message_box2_config:get(database_dir),
    Path = DB_DIR ++ FileName,
    {DiscName, Path}.

%%
%% @doc sleep function
%%

sleep(Msec) when is_integer(Msec) ->
    receive
    after Msec -> ok
    end.

%%
%% @doc create md5 password
%%

get_md5_password(User, RawPassword) when is_list(RawPassword) ->
    crypto:md5([RawPassword, User#user.name, User#user.mail,
                ?MD5_KEY1, ?MD5_KEY2, ?MD5_KEY3]).
    
get_onetime_password(User, RawPassword) when is_list(RawPassword) ->
    {Year, Month, Day} = date(),
    {Hour, Min, Sec} = time(),
    DateTimeStr = 
        lists:flatten(io_lib:format("~w~w~w~w~w~w", 
                                    [Year, Month, Day, Hour, Min, Sec])),

    crypto:md5([RawPassword, User#user.name, User#user.mail,
                ?MD5_KEY1, ?MD5_KEY2, ?MD5_KEY3, 
                DateTimeStr]).

exist_in_list(List, Elem) ->
    case List of
	[] -> false;
	[E | Tail] -> case E of
			  Elem -> true;
			  _ -> exist_in_list(Tail, Elem)
		      end
    end.

authenticate(User, Password, OneTimePasswordList) ->
    case exist_in_list(OneTimePasswordList, Password) of
	true -> {ok, authenticated};
	false -> authenticate(User, Password)
    end. 

authenticate(User, RawPassword) ->
    Md5Password = get_md5_password(User, RawPassword),
    case User#user.password of
	Md5Password -> {ok, authenticated};
	_ ->           {error, unauthenticated}
    end.
	    
icon_path(Name) when is_atom(Name) -> 
    Dir = message_box2_config:get(icon_dir),
    Dir ++ atom_to_list(Name).

%%
%% @doc ets shurink function
%%
-spec(shurink_ets(Tid::tid(), MaxCount::integer()) -> ok).

shurink_ets(Tid, MaxCount) ->
    case ets:first(Tid) of
        '$end_of_table' -> 
            ok;
        First ->
            shurink_ets(Tid, MaxCount, First, 1)
    end.

shurink_ets(Tid, MaxCount, Index, Count) ->
    case ets:next(Tid, Index) of
        '$end_of_table' -> 
            ok;
        Next ->
            if Count > MaxCount -> ets:delete(Tid, Next);
               true -> ok
            end,
            shurink_ets(Tid, MaxCount, Next, Count + 1)
    end.
