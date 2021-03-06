%%%-------------------------------------------------------------------
%%% @author Huseyin Yilmaz <huseyin@huseyins-air.home>
%%% @copyright (C) 2014, Huseyin Yilmaz
%%% @doc
%%%
%%% @end
%%% Created : 13 Jul 2014 by Huseyin Yilmaz <huseyin@huseyins-air.home>
%%%-------------------------------------------------------------------
-module(machete_mnesia).

%% API
-export([init/0,
         insert_url/1]).

-compile(export_all).

-record(url, {code::binary(),
              url::binary()}).

-record(counter, {name::term(),
                  value::integer()}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts mnesia.
%% @end
%%--------------------------------------------------------------------

init() ->
    ok = ensure_mnesia_dir(),
    ok = mnesia:start(),
    ok = ensure_mnesia_running(),
    ok = ensure_schema(),
    lager:debug("Waiting for tables to initialize"),
    ok = mnesia:wait_for_tables(names(), 30000),
    lager:debug("Table initialization complete").

-spec insert_url(binary() | list()) -> binary().
insert_url(Url) when is_list(Url) -> insert_url(list_to_binary(Url));
insert_url(Url) ->
    Code = get_url_code(),
    mnesia:dirty_write(#url{code=Code, url=Url}),
    Code.
    %% mnesia:transaction(fun()-> mnesia:write(#url{code=get_url_code(), url=Url}) end).

get_url(Code) when is_list(Code) -> get_url(list_to_binary(Code));
get_url(Code)->
    case mnesia:dirty_read(url, Code) of
        [#url{url=Url}] -> Url;
        [] -> not_found
    end.





%%%===================================================================
%%% Internal functions
%%%===================================================================

start()->
    lager:debug("starting mnesia."),
    ok = mnesia:start().


stop()->
    lager:debug("stop mnesia."),
    mnesia:stop().

ensure_schema() ->
    case absent_tables() of
        [] ->
            lager:debug("schema integrity is ensured"),
            ok;
        _ ->
            lager:warning("Schema is not complete. Creating new schema"),
            create_schema(),
            create_mnesia_tables(absent_tables()),
            lager:info("Schema creation. complete."),
            lager:debug("rechecking integrity"),
            ensure_schema()
    end.

create_schema() ->
    stop(),
    ensure_mnesia_not_running(),
    lager:debug("creating mnesia schema"),
    _ = mnesia:delete_schema([node()]),
    ok = mnesia:create_schema([node()]),
    lager:debug("starting mnesia"),
    start(),
    ensure_mnesia_running().


create_mnesia_tables(Tables) ->
    lists:foreach(fun ({Tab, TabDef}) ->
                          case mnesia:create_table(Tab, TabDef) of
                              {atomic, ok} -> ok;
                              {aborted, Reason} ->
                                  throw({error, {table_creation_failed,
                                                 Tab, TabDef, Reason}})
                          end
                  end, Tables),
    ok.


ensure_mnesia_running() ->
    case mnesia:system_info(is_running) of
        yes ->
            ok;
        starting ->
            wait_for(mnesia_running),
            ensure_mnesia_running();
        Reason when Reason =:= no; Reason =:= stopping ->
            throw({error, mnesia_not_running})
    end.

ensure_mnesia_not_running() ->
    case mnesia:system_info(is_running) of
        no ->
            ok;
        stopping ->
            wait_for(mnesia_not_running),
            ensure_mnesia_not_running();
        Reason when Reason =:= yes; Reason =:= starting ->
            throw({error, mnesia_unexpectedly_running})
    end.

ensure_mnesia_dir() ->
    MnesiaDir = dir() ++ "/",
    case filelib:ensure_dir(MnesiaDir) of
        {error, Reason} ->
            throw({error, {cannot_create_mnesia_dir, MnesiaDir, Reason}});
        ok ->
            ok
    end.

dir() -> mnesia:system_info(directory).

table_list()->
    lists:sort(lists:delete(schema, mnesia:system_info(tables))).

absent_tables()->
    Table_list = table_list(),
    lists:foldl(fun({Table_name, _}=Item, Sum)->
                        case lists:member(Table_name, Table_list) of
                            true ->
                                Sum;
                            false ->
                                [Item | Sum]
                        end
                end,
                [],
                definitions()).


wait_for(Condition) ->
    lager:info("Waiting for ~p...", [Condition]),
    timer:sleep(1000).

names() -> [Tab || {Tab, _} <- definitions()].

definitions()->
    [{url,
      [{record_name, url},
       {attributes, record_info(fields, url)},
       {disc_only_copies, [node()]}]},
     {counter,
      [{record_name, counter},
       {attributes, record_info(fields, counter)},
       {disc_copies, [node()]}]}
    ].

%%%%%%%%%%%%%%%%%%%%%%%
%% Counter functions %%
%%%%%%%%%%%%%%%%%%%%%%%
get_url_code() ->
    list_to_binary(string:to_lower(integer_to_list(bump(url), 36))).

bump(Type) ->
    bump(Type, 1).

bump(Type, Inc) ->
    mnesia:dirty_update_counter(counter, Type, Inc).
