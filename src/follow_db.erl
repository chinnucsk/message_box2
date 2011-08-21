%% File : follow_db.erl
%% Description : user follow relationship database.

-module(follow_db).
-include_lib("eunit/include/eunit.hrl").
-include("../include/message_box.hrl").
-include("../include/message.hrl").
-include("../include/user.hrl").

-export([init/1]).
-export([close_tables/2, save_follow_user/3, delete_follow_user/3,
        get_follow_ids/1, map_do/2, is_follow/2]).

%%--------------------------------------------------------------------
%%
%% @doc load follow users from dets to ets.
%%
%% @end
%%--------------------------------------------------------------------
-spec(init(UserName::atom()) -> {ok, Tid::pid()}).

init(UserName) ->
    process_flag(trap_exit, true),

    DB_DIR = message_box2_config:get(database_dir),
    case file:make_dir(DB_DIR ++ atom_to_list(UserName)) of
        ok -> ok;
        {error, eexist} -> ok
    end,

    {ok, Tid} = create_tables(UserName),
    restore_table(Tid, UserName),
    {ok, Tid}.

    
%%--------------------------------------------------------------------
%%
%% @doc create table ets and dets.
%%
%% @end
%%--------------------------------------------------------------------
-spec(create_tables(Device::atom()) -> {ok, Tid::pid()}).

create_tables(UserName) ->  
    Tid = ets:new(follow, [ordered_set, {keypos, #follow.id}]),
    {DiscName, FileName} = dets_info(UserName),
    dets:open_file(DiscName, [{file, FileName}, {keypos, #follow.id}]),
    {ok, Tid}.

%%--------------------------------------------------------------------
%%
%% @doc load follow users from dets to ets.
%%
%% @end
%%--------------------------------------------------------------------
-spec(restore_table(Tid::tid(), UserName::atom()) -> ok).

restore_table(Tid, UserName) ->
    Insert = fun(#follow{id=_Id, datetime=_DateTime} = Follow)->
		     ets:insert(Tid, Follow),
		     continue
	     end,

    {Dets, _} = dets_info(UserName),
    dets:traverse(Dets, Insert),
    ok.

%%--------------------------------------------------------------------
%%
%% @doc close ets and dets database.
%%
%% @end
%%--------------------------------------------------------------------
-spec(close_tables(Tid::tid(), UserName::atom()) -> 
             ok | {error, Reason::term()}).

close_tables(Tid, UserName) ->
    {Dets, _} = dets_info(UserName),
    ets:delete(Tid),
    dets:close(Dets).

%%--------------------------------------------------------------------
%%
%% @doc save user to follow database.
%%
%% @end
%%--------------------------------------------------------------------
-spec(save_follow_user(Tid::tid(), User::#user{}, Id::integer()) ->
             ok | {error, already_following}).

save_follow_user(Tid, User, Id) ->
    Follow = #follow{id=Id, datetime={date(), time()}},

    case is_following(User, Id) of
	true -> {error, already_following};
	false ->
            {Dets, _} = dets_info(User#user.name),
	    ets:insert(Tid, Follow),
	    dets:insert(Dets, Follow),
	    ok
    end.

%%--------------------------------------------------------------------
%%
%% @doc delet user from follow database.
%%
%% @end
%%--------------------------------------------------------------------
-spec(delete_follow_user(Tid::tid(), User::#user{}, Id::integer()) -> 
             {ok, deleted} | {error, not_following}).

delete_follow_user(Tid, User, Id) ->
    case is_following(Tid, Id) of
	true ->
	    {Dets, _} = dets_info(User#user.name),
	    ets:delete(Tid, Id),
	    dets:delete(Dets, Id),
	    {ok, deleted};
	false -> {error, not_following}
    end.

%%--------------------------------------------------------------------
%%
%% @doc get all follow users id.
%%
%% @end
%%--------------------------------------------------------------------
-spec(get_follow_ids(Tid::tid()) -> [#follow{}]).

get_follow_ids(Tid) ->
    case ets:first(Tid) of
	'$end_of_table' -> [];
	First -> collect_id(Tid, First, [First])
    end.

%%--------------------------------------------------------------------
%%
%% @doc do function to all users.
%%
%% @end
%%--------------------------------------------------------------------
-spec(map_do(Tid::tid(), Fun::fun()) -> ok).

map_do(Tid, Fun) ->
    case ets:first(Tid) of
	'$end_of_table' ->
	    ok;
	First ->
	    [Follow] = ets:lookup(Tid, First),
	    Fun(Follow),
	    map_do(Tid, Fun, First)
    end.

%%--------------------------------------------------------------------
%%
%% @doc check followin user or not.
%%
%% @end
%%--------------------------------------------------------------------
-spec(is_follow(Tid::tid(), UserId::integer()) -> true|false).

is_follow(Tid, UserId) ->
    case ets:lookup(Tid, UserId) of
        [_FollowingUser] -> true;
        [] -> false
    end.

%%--------------------------------------------------------------------
%% local functions
%%--------------------------------------------------------------------

-spec(collect_id(Tid::tid(), Before::integer(), Result::[integer()]) ->
             [integer()]).

collect_id(Tid, Before, Result) ->
    case ets:next(Tid, Before) of
	'$end_of_table' -> Result;
	FollowId -> collect_id(Tid, FollowId, [FollowId | Result])
    end.	    

-spec(is_following(Tid::tid(), Id::integer()) -> true | false).

is_following(Tid, Id) ->
    case ets:lookup(Tid, Id) of
	[_Follow] -> true;
	[] -> false
    end.    

-spec(dets_info(UserName::atom()) -> {Dets::atom(), FileName::string()}).

dets_info(UserName)->
    DiscName = list_to_atom(atom_to_list(UserName) ++ "_FollowDisc"),
    DB_DIR = message_box2_config:get(database_dir),
    FileName = DB_DIR ++ atom_to_list(UserName) ++ "follow",
    {DiscName, FileName}.

-spec(map_do(Tid::tid(), Fun::fun(), Entry::integer()) -> term()).

map_do(Tid, Fun, Entry) ->
    case ets:next(Tid, Entry) of
	'$end_of_table' ->
	    ok;
	Next ->
	    [Follow] = ets:lookup(Tid, Next),
	    Fun(Follow),
	    map_do(Tid, Fun, Next)
    end.
