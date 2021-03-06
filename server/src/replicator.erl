%% Hotchpotch
%% Copyright (C) 2011  Jan Klötzke <jan DOT kloetzke AT freenet DOT de>
%%
%% This program is free software: you can redistribute it and/or modify
%% it under the terms of the GNU General Public License as published by
%% the Free Software Foundation, either version 3 of the License, or
%% (at your option) any later version.
%%
%% This program is distributed in the hope that it will be useful,
%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%% GNU General Public License for more details.
%%
%% You should have received a copy of the GNU General Public License
%% along with this program.  If not, see <http://www.gnu.org/licenses/>.

-module(replicator).
-behaviour(supervisor).

-export([start_link/0]).
-export([cancel/0, event_modified/2, replicate_rev/4, replicate_rev_sync/4,
         replicate_doc/4, replicate_doc_sync/4]).
-export([init/1]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% External interface...
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

start_link() ->
	Result = supervisor:start_link({local, replicator}, ?MODULE, []),
	%io:format("replicator: start_link ~w~n", [Result]),
	Result.

event_modified(Doc, StoreGuid) ->
	case volman:store(StoreGuid) of
		{ok, StorePid} ->
			start_child([{modified, Doc, {StoreGuid, StorePid}}]);

		error ->
			ok
	end.

replicate_doc(Doc, Depth, SrcStores, DstStores) ->
	start_child([{replicate_doc, Doc, Depth, SrcStores, DstStores, true}]).

replicate_doc_sync(Doc, Depth, SrcStores, DstStores) ->
	start_child_sync([{replicate_doc, Doc, Depth, SrcStores, DstStores, true}]).

replicate_rev(Rev, Depth, SrcStores, DstStores) ->
	start_child([{replicate_rev, Rev, Depth, SrcStores, DstStores, true}]).

replicate_rev_sync(Rev, Depth, SrcStores, DstStores) ->
	start_child_sync([{replicate_rev, Rev, Depth, SrcStores, DstStores, true}]).

cancel() ->
	% TODO
	ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Callback functions...
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

init([]) ->
	{ok, {
		{simple_one_for_one, 1, 10},
		[{
			replicator,
			{replicator_worker, start_link, []},
			temporary,
			brutal_kill,
			worker,
			[]
		}]
	}}.


start_child(Args) ->
	supervisor:start_child(replicator, Args).

start_child_sync(Args) ->
	Ref = make_ref(),
	case start_child(Args ++ [{self(), Ref}]) of
		{ok, _WorkerPid} ->
			receive
				{Ref, Reply} -> Reply
			%after
			%	% FIXME: this is deemed to FAIL
			%	60000 -> {error, timeout}
			end;

		{error, _} ->
			{error, enomem, []}
	end.

