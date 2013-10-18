%%%-------------------------------------------------------------------
%%% @author Khashayar <khashayar@khashayar>
%%% @copyright (C) 2013, Khashayar
%%% @doc
%%%     This process will pars the a certain Source of project
%%%     Parsing happens in 2 phases,
%%%     First phase to grab the URL from web and find the next page
%%%     After this depened on the situation the proper message is sent
%%%     back to CUnit
%%%     Second phase is parsing the data and translate it
%%% @end
%%% Created : 25 Jul 2013 by Khashayar <khashayar@khashayar>
%%%-------------------------------------------------------------------
-module(erlproject_parser).

-export([start/1, init/1, crawl/2, parse/2]).

-include("records.hrl").

start(Url) ->
    %%    ?L("spawn(erlproject_parser) ",[{url, Url}]),
    spawn(erlproject_parser, init, [Url]).

init({Source,Url}) ->
    error_logger:info_report("erlproject_parser:init",{source, Source}),
    crawl(Source,Url).
crawl(git, Url) ->
    erlproject_git_parser:start(Url);

%% git requests are handled in a different module to avoid process floods 
%% crawl(git, Url) ->
%%     ?L("erlproject_parser:crawl, git, Url = ",{reason, Url}),
%%     case erlproject_funs:read_web(git,Url) of
%% 	{limit, T} ->
%% 	    gen_server:cast(erlproject_cunit, {wait, T, {git,Url}}); 
%% 	{success, last, List} ->
%%     	    gen_server:cast(erlproject_cunit, last),
%% 	    parse(git, List);
%% 	{success, Next, List} ->
%% 	    gen_server:cast(erlproject_cunit, {next, {git,Next}}),
%% 	    parse(git, List);
%% 	{error,Reason} ->
%% 	    gen_server:cast(erlproject_cunit, {error, {Reason,Url}});
%% 	_ ->
%% 	    io:format("SOMETHING IS HAPPENING ~p~n" , [Url])
%%     end;

crawl(git_language, Url) ->
    ?L(" erlproject_parser:crawl, git_language",
       {url, Url}),
    case erlproject_funs:read_web(default,Url) of
	{success,{Headers,Body}} ->
	    case erlproject_funs:check(Headers) of 
		ok ->
		    L = string:tokens(Url, "/"),
		    Name = lists:nth(4,L) ++ "/" ++ lists:nth(5,L),
		    gen_server:cast(erlproject_db,
				    {write, git_language, {Body,Name}});
		error ->
		    gen_server:cast(erlproject_cunit, 
				    {error, {headers,Url}});		
		Limit ->
		    gen_server:cast(erlproject_cunit, 
				    {wait, Limit, {git_language,Url}})
	    end;
	{error, Reason} ->
	    gen_server:cast(erlproject_cunit, {error, {Reason,Url}})
    end;    
crawl(git_commit, Url) ->
    ?L("erlproject_parser:crawl, git_commit, Url = ",{reason, Url}),
    case erlproject_funs:read_web(default,Url) of
	{success,{Headers,Body}} ->
	    case erlproject_funs:check(Headers) of 
		ok ->
		    {array,List} = mochijson:decode(Body),
		    parse(git_commit, List);
		error ->
		    gen_server:cast(erlproject_cunit, 
				    {error, {headers,Url}});		
		Limit ->
		    gen_server:cast(erlproject_cunit, 
				    {wait, Limit, {git_commit,Url}})
	    end;
	{error, Reason} ->
	    gen_server:cast(erlproject_cunit, {error, {Reason,Url}})
    end;    
crawl(google, Url) ->
    ?L("erlproject_parser:crawl, google, Url = ",{reason, Url}),
    case erlproject_funs:read_web(default,Url) of
	{success,{_Headers,Body}} ->
	    Html = mochiweb_html:parse(Body),
	    T = erlproject_funs:get_value([Html], "a", []),
	    case erlproject_funs:grab_next(google, T) of
		last ->
		    gen_server:cast(erlproject_cunit, last);
		Next ->
		    gen_server:cast(erlproject_cunit, 
				    {next, {google,Next}})
	    end,
	    parse(google,Html);
	{error, Reason} ->
	    gen_server:cast(erlproject_cunit, {error, {Reason,Url}})
    end;
crawl(sourceforge, Url) ->
    ?L("erlproject_parser:crawl, sourceforge, Url = ",{reason, Url}),
    case erlproject_funs:read_web(default,Url) of
        {success,{_Headers, ?SOURCEFORGE_OVERLOAD}} ->
            %% "Too many requests, please try again later."
            %% Skip sourceforge until the next iteration
            Reason = "sourceforge overloaded",    
            gen_server:cast(erlproject_cunit, {error, {Reason,Url}});
	{success,{_Headers,Body}} ->
	    Html = mochiweb_html:parse(Body),
	    Links = erlproject_funs:get_value([Html], "a", []),
	    parse(sourceforge,Links),
	    case erlproject_funs:grab_next(sf, Links) of
		last ->
		    gen_server:cast(erlproject_cunit, last);
		Next ->
                    timer:sleep(500), %% wait a bit to avoid massive storm
		    gen_server:cast(erlproject_cunit, 
				    {next, {sourceforge,Next}})
            end;
	{error, Reason} ->
	    gen_server:cast(erlproject_cunit, {error, {Reason,Url}})
    end;
crawl(sfapi,Url) ->
    ?L("erlproject_parser:crawl, sfapi, Url = ",{reason, Url}),
    error_logger:info_report("erlproject_parser:crawl, sfapi, Url = ",{reason, Url}),
    case erlproject_funs:read_web(default,Url) of
        {success,{_Headers, ?SOURCEFORGE_OVERLOAD}} ->
            %% "Too many requests, please try again later."
            %% Skip sourceforge until the next iteration
            Reason = "sourceforge overloaded",    
            gen_server:cast(erlproject_cunit, {error, {Reason,Url}});
	{success,{_Headers,Body}} ->
            parse(sfapi,Body);
        {error, Reason} ->
            gen_server:cast(erlproject_cunit, {error, {Reason,Url}})
    end;
crawl(bitbucket, Url) ->
    ?L("erlproject_parser:crawl, bitbucket, Url = ",{reason, Url}),
    case erlproject_funs:read_web(default,Url) of
	{success,{_Headers,Body}} ->
	    Html = mochiweb_html:parse(Body),
	    Links = erlproject_funs:get_value([Html], "a", []),
	    case erlproject_funs:grab_next(bitbucket, Links) of
		last ->
		    gen_server:cast(erlproject_cunit, last);
		Next ->
		    gen_server:cast(erlproject_cunit, 
				    {next, {bitbucket,Next}})
	    end,
	    parse(bitbucket, Links);
	{error, Reason} ->
	    gen_server:cast(erlproject_cunit, {error, {Reason,Url}})
    end;
crawl(bbapi,Url) ->
    ?L("erlproject_parser:crawl, bbapi, Url = ",[{reason, Url}]),
    case erlproject_funs:read_web(default,Url) of
        {success,{_Headers,Body}} ->
            parse(bbapi,Body);
        {error, Reason} ->
            gen_server:cast(erlproject_cunit, {error, {Reason,Url}})
    end.

parse(git, List) ->
    Auth = "?access_token=e62fdebb6e20c178dd30febcc7126e06367dd975",
    Extract = fun(X) -> 
		      erlproject_funs:extract(git,X) 
	      end, 
    Res = lists:map(Extract , List),
    Cast = fun(X) -> 
		   Languages = X#git.languages_url ++ Auth,
		   Commits = hd(string:tokens(X#git.commits_url, "{")) 
                       ++ Auth ++ "&per_page=3",
		   gen_server:cast(erlproject_cunit, 
				   {language, {git_language, Languages}}),
		   gen_server:cast(erlproject_cunit, 
				   {commit, {git_commit, Commits}}),
		   gen_server:cast(erlproject_db,{write, git,  X}) 
	   end,
    lists:foreach(Cast, Res);

parse(git_commit, List) ->
    Extract = fun(X) ->
		      erlproject_funs:extract(git_commit, X)
	      end,
    Res = lists:map(Extract, List),
    commiter(Res);

parse(google,Html) ->
    T = erlproject_funs:get_value([Html], "table", []),
    Extract = fun(X) -> 
		      erlproject_funs:extract(google,X) 
	      end, 
    Res = lists:map(Extract , T),
    Cast = fun(X) ->
		   case X of
		       not_valid ->
			   ok;
		       Elem ->
			   gen_server:cast(erlproject_db,
					   {write, google,  Elem}) 
		   end
	   end,
    lists:foreach(Cast, Res);

parse(sourceforge, Links) ->
    Projects = erlproject_funs:get_content(Links,
					   {"class" ,"project-icon"},
					   "href"),
    Extract = fun(X) ->
		      Name =lists:nth(2, string:tokens(X,"/")),
		      "http://sourceforge.net/api/project/name/" ++
			  Name ++ "/json"
	      end,
    Res = lists:map(Extract,Projects),
    crawl_sfapi_projects(Res);
%% Spawn = fun(X) ->
%%                 %%% wait a bit to avoid massive process storm
%%                 timer:sleep(1000),
%%                 erlproject_parser:start({sfapi,X})
%%         end,
%% lists:foreach(Spawn, Res);    

parse(sfapi,Body) ->
    case erlproject_funs:extract(sfapi, mochijson:decode(Body)) of
	Data = #git{} ->
	    gen_server:cast(erlproject_db, {write, sfapi,  Data}); 
	Reason ->
	    error_logger:info_report(["Pasing SF MOCHI",
				      {reason,Reason}])	   

    end;

parse(bitbucket, Links) ->
    Projects = erlproject_funs:get_content(Links,
					   {"class" ,"avatar-link"},
					   "href"),
    Extract = fun(X) ->
		      "https://bitbucket.org/api/1.0/repositories" ++
			  X
	      end,
    Res = lists:map(Extract,Projects),
    Spawn = fun(X) ->
		    erlproject_parser:start({bbapi,X})
	    end,
    lists:foreach(Spawn, Res);

parse(bbapi,Body) ->
    case erlproject_funs:extract(bbapi, mochijson:decode(Body)) of
	Data = #git{} ->
	    gen_server:cast(erlproject_db, {write, bbapi,  Data}); 
	Reason ->
	    error_logger:info_report(["Pasing BB MOCHI",
				      {reason,Reason}])	   

    end.



commiter(List) ->
    commiter(List, 1).

commiter([], _) ->
    ok;
commiter([H|T],N) ->
    gen_server:cast(erlproject_db, 
		    {write, git_commit, {N,H}}),
    commiter(T,N+1).


crawl_sfapi_projects([]) -> ok;
crawl_sfapi_projects([X|Rem]) ->
    erlproject_parser:crawl(sfapi,X),
                                                % there is no need for a new project, just crawl it
    crawl_sfapi_projects(Rem).
