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

-module(store).

-export([guid/1, statfs/1, contains/2, lookup/2, stat/2]).
-export([put_doc/4, put_rev_start/3, put_rev_part/3, put_rev_abort/1,
	put_rev_commit/1]).
-export([close/1, commit/2, create/4, fork/4, get_parents/1, get_type/1,
	peek/2, read/4, resume/4, set_parents/2, set_type/2, truncate/3, update/4,
	write/4, suspend/2, get_links/1, set_links/2]).
-export([delete_rev/2, delete_doc/3, forget/3]).
-export([sync_get_changes/2, sync_set_anchor/3, sync_finish/2]).
-export([hash_revision/1]).

-include("store.hrl").

%% @doc Get GUID of a store
%% @spec guid(Store::pid()) -> guid()
guid(Store) ->
	call_store(Store, guid, <<0:128>>).

%% @doc Get file system statistics
%% @spec statfs(Store::pid()) -> {ok, #fs_stat{}} | {error, Reason}
statfs(Store) ->
	call_store(Store, statfs).

%% @doc Lookup a document.
%%
%% Returns the current revision and any pending preliminary revisions if the
%% document is found in the store, or `error' if no such document exists.
%%
%% @spec lookup(Store, Doc) -> {ok, Rev, PreRevs} | error
%%       Store = pid()
%%       Doc = Rev = guid()
%%       PreRevs = [guid()]
lookup(Store, Doc) ->
	call_store(Store, {lookup, Doc}, error).

%% @doc Check if a revision exists in the store
%% @spec contains(Store, Rev) -> bool()
%%       Store = pid()
%%       Rev = guid()
contains(Store, Rev) ->
	call_store(Store, {contains, Rev}, false).

%% @doc Stat a revision.
%%
%% Returns information about a revision if it is found on the store, or `error'
%% if no such revision exists. The returned information is a #stat{} record
%% containing the following fields:
%%
%%   flags = integer()
%%   parts = [{FourCC::binary(), Size::interger(), Hash::guid()}]
%%   parents = [guid()]
%%   mtime = integer()
%%   type = binary()
%%   creator = binary()
%%
%% @spec stat(Store, Rev) -> {ok, Stat} | {error, Reason}
%%       Store = pid()
%%       Rev = guid()
%%       Stat = #stat{}
%%       Reason = ecode()
stat(Store, Rev) ->
	call_store(Store, {stat, Rev}).

%% @doc Start reading a revision.
%%
%% Returns the handle when ready, or an error code.
%%
%% @spec peek(Store, Rev) -> {ok, Handle} | {error, Reason}
%%       Store = pid()
%%       Handle = pid()
%%       Rev = guid()
%%       Reason = ecode()
peek(Store, Rev) ->
	call_store(Store, {peek, Rev}).

%% @doc Create a new, empty document.
%%
%% Returns a handle for the following read/write functions to fill it. The
%% handle can only be commited or aborted but not suspended because the new
%% document will not show up in the store until a sucsessful commit.
%%
%% @spec create(Store, Doc, Type, Creator) -> {ok, Handle} | {error, Reason}
%%         Store = pid()
%%         Handle = pid()
%%         Doc = guid()
%%         Type, Creator = binary()
%%         Reason = ecode()
create(Store, Doc, Type, Creator) ->
	call_store(Store, {create, Doc, Type, Creator}).

%% @doc Derive a new document from an existing revision
%%
%% Returns a handle for the following read/write functions to update the new
%% document. The new revision will start with the content of the StartRev
%% revision. The handle can only be commited or aborted but not suspended
%% because the new document will not show up in the store until a sucsessful
%% commit.
%%
%% @spec fork(Store, Doc, StartRev, Creator) -> {ok, Handle} | {error, Reason}
%%         Store = pid()
%%         Handle = pid()
%%         StartRev, Doc = guid()
%%         Creator = binary()
%%         Reason = ecode()
fork(Store, Doc, StartRev, Creator) ->
	call_store(Store, {fork, Doc, StartRev, Creator}).

%% @doc Update an existing document
%%
%% The new revision will start with the content of the StartRev revision and
%% will have StartRev as its sole parent. If Doc points already to another
%% revision then the call will fail.
%%
%% @spec update(Store, Doc, StartRev, Creator) -> {ok, Handle} | {error, Reason}
%%        Store = pid()
%%        Handle = pid()
%%        Doc, StartRev = guid()
%%        Creator = keep | binary()
%%        Reason = ecode()
update(Store, Doc, StartRev, Creator) ->
	call_store(Store, {update, Doc, StartRev, Creator}).

%% @doc Resume writing to a document
%%
%% This will open a preliminary revision that was previously suspended. The
%% content will be exactly the same as when it was suspended, including its
%% parents. StartRev will be kept as pending preliminary revision (until
%% overwritten by either commit/2 or suspend/1).
%%
%% @spec resume(Store, Doc, PreRev, Creator) -> {ok, Handle} | {error, Reason}
%%        Store = pid()
%%        Handle = pid()
%%        Doc, PreRev = guid()
%%        Creator = keep | binary()
%%        Reason = ecode()
resume(Store, Doc, PreRev, Creator) ->
	call_store(Store, {resume, Doc, PreRev, Creator}).

%% @doc Read a part of a document
%%
%% Returns the requested data. Trying to read a non-existing part yields
%% {error, enoent}. May return less data if the end of the part was hit.
%%
%% @spec read(Handle, Part, Offset, Length) -> {ok, Data} | {error, Reason}
%%       Handle = pid()
%%       Part = Data = binary()
%%       Offset = Length = integer()
%%       Reason = ecode()
read(Handle, Part, Offset, Length) ->
	call_store(Handle, {read, Part, Offset, Length}).

%% @doc Write a part of a document
%%
%% Writes the given data at the requested offset of the part. If the part does
%% not exist yet it will be created.
%%
%% @spec write(Handle, Part, Offset, Data) -> ok | {error, Reason}
%%       Handle = pid()
%%       Part = Data = binary()
%%       Offset = integer()
%%       Reason = ecode()
write(Handle, Part, Offset, Data) ->
	call_store(Handle, {write, Part, Offset, Data}).

%% @doc Truncate part
%%
%% Truncates part at the given offset. If the part does not exist yet it will
%% be created.
%%
%% @spec truncate(Handle, Part, Offset) -> ok | {error, Reason}
%%       Handle = pid()
%%       Part = binary()
%%       Offset = integer()
%%       Reason = ecode()
truncate(Handle, Part, Offset) ->
	call_store(Handle, {truncate, Part, Offset}).

% {ok, binary()} | {error, Reason}
get_type(Handle) ->
	call_store(Handle, get_type).

% ok | {error, Reason}
set_type(Handle, Type) ->
	call_store(Handle, {set_type, Type}).

% {ok, [guid()]} | {error, Reason}
get_parents(Handle) ->
	call_store(Handle, get_parents).

% ok | {error, Reason}
set_parents(Handle, Parents) ->
	call_store(Handle, {set_parents, Parents}).

% {ok, {SDL, WDL, SRL, WRL, DocMap}} | {error, Reason}
get_links(Handle) ->
	call_store(Handle, get_links).

% ok | {error, Reason}
set_links(Handle, Links) ->
	call_store(Handle, {set_links, Links}).

%% @doc Commit a new revision
%%
%% One of the parents of this new revision must point to the current revision
%% of the document, otherwise the function will fail with a `econflict' error
%% code. The handle remains writable in this case and the caller may either
%% rebase the revision and try again or suspend the handle to keep the changes.
%%
%% If the new revision could be committed then its identifier will be returned.
%% If the handle was resumed from a preliminary revision then this preliminary
%% revision will be removed from the list of pending preliminary revisions. In
%% case of severe errors the function will fail with an apropriate error code.
%%
%% The handle will be read only after the call if the commit succeeds. In case
%% the commit fails, e.g. due to a conflict the handle will still be writable.
%%
%% @spec commit(Handle, Mtime) -> {ok, Rev} | {error, Reason}
%%       Handle = pid()
%%       Mtime = integer()
%%       Rev = guid()
%%       Reason = ecode()
commit(Handle, Mtime) ->
	call_store(Handle, {commit, Mtime}).

%% @doc Suspend a handle
%%
%% This function will create a temporary revision with the changes made so far
%% and will enqueue it as a pending preliminary revisions of the affected
%% document. The operation should only fail on io-errors or when trying to
%% suspend a handle which was obtained from create/4 or fork/4.
%%
%% The handle can be resumed later by calling resume/4. If the resulting handle
%% is successfully commited or again suspended then the original preliminary
%% revision is removed from the document. The preliminary revision can also be
%% removed explicitly by calling forget/3.
%%
%% The handle will be read only after the call if the operation succeeds. In
%% case the operation fails the handle will still be writable.
%%
%% @spec suspend(Handle, Mtime) -> {ok, Rev} | {error, Reason}
%%       Handle = pid()
%%       Mtime = integer()
%%       Rev = guid()
%%       Reason = ecode()
suspend(Handle, Mtime) ->
	call_store(Handle, {suspend, Mtime}).

%% @doc Close a handle
%%
%% Discards the handle. Throws away any changes which have not been committed
%% yet. The handle will be invalid after the call.
%%
%% @spec close(Handle) -> ok
%%       Handle = pid()
close(Handle) ->
	call_store(Handle, close).

%% @doc Remove a pending preliminary revision from a document.
%%
%% @spec forget(Store, Doc, PreRev) -> ok | {error, Reason}
%%       Store = pid()
%%       Doc, PreRev = guid()
%%       Reason = ecode()
forget(Store, Doc, PreRev) ->
	call_store(Store, {forget, Doc, PreRev}).

%% @doc Delete a document and release any referenced revisions.
%%
%% Normally documents should not be deleted explicitly but indirectly through
%% automatic garbage collection when they are no longer referenced inside the
%% store.
%%
%% @spec delete_doc(Store, Doc, Rev) -> ok | {error, Reason}
%%       Store = pid()
%%       Doc, Rev = guid()
%%       Reason = ecode()
delete_doc(Store, Doc, Rev) ->
	call_store(Store, {delete_doc, Doc, Rev}).

%% @doc Delete a revision and release any referenced parent revisions
%%
%% This is normally used to explicitly delete old, unused revisions of a
%% document.
%%
%% @spec delete_rev(Store, Rev) -> ok | {error, Reason}
%%       Store = pid()
%%       Rev = guid()
%%       Reason = ecode()
delete_rev(Store, Rev) ->
	call_store(Store, {delete_rev, Rev}).

%% @doc Put/update a document in the store
%%
%% Let's a document point to a new revision. If the Doc does not exist yet then it
%% is created and points to NewRev. If the Doc exits it must either point
%% OldRev or NewRev, otherwise the call will fail.
%%
%% @spec put_doc(Store, Doc, OldRev, NewRev) -> ok | {error, Reason}
%%       Store = pid()
%%       Doc = OldRev = NewRev = guid()
%%       Reason = ecode()
put_doc(Store, Doc, OldRev, NewRev) ->
	call_store(Store, {put_doc, Doc, OldRev, NewRev}).

%% @doc Put/import a revision into the store.
%%
%% The function takes the specification of the whole revision and returns the
%% list of missing parts which the caller has to supply by subsequent
%% put_rev_part/3 calls. If all parts are already available in the store then
%% the function just returns `ok'.
%%
%% @spec put_rev_start(Store, Rev, Revision) -> Result
%%       Store = pid()
%%       Rev = guid()
%%       Revision = #revision
%%       Result = ok | {ok, MissingParts, Importer} | {error, Reason}
%%       MissingParts = [FourCC]
%%       Importer = pid()
%%       Reason = ecode()
put_rev_start(Store, Rev, Revision) ->
	call_store(Store, {put_rev, Rev, Revision}).

%% @doc Add data to a revision that's imported
%%
%% @spec put_rev_part(Importer, Part, Data) -> ok | {error, Reason}
%%       Importer = pid()
%%       Part = Data = binary()
%%       Reason = ecode()
put_rev_part(Importer, Part, Data) ->
	call_store(Importer, {put_part, Part, Data}).

%% @doc Abort importing a revision
%% @spec put_rev_abort(Importer::pid()) -> none()
put_rev_abort(Importer) ->
	call_store(Importer, abort, ok).

%% @doc Finish importing a revision
%% @spec put_rev_commit(Importer::pid()) -> ok | {error, Reason}
%%       Importer = pid()
%%       Reason = ecode()
put_rev_commit(Importer) ->
	call_store(Importer, commit).


%% @doc Get changes since the last sync point of peer store
%%
%% The caller is also recorded as the synchronizing process. Only one sync
%% process is allowed per peer store. The store will trap the exit of the
%% caller but the caller may also release the lock by calling sync_finish/2.
%%
%% @spec sync_get_changes(Store, PeerGuid) -> Result
%%       Store = pid()
%%       PeerGuid = guid()
%%       Result = {ok, Backlog} | {error, Reason}
%%       Backlog = [{Doc::guid(), SeqNum::integer()}]
sync_get_changes(Store, PeerGuid) ->
	call_store(Store, {sync_get_changes, PeerGuid}).


%% @doc Set sync point of peer store to new generation
%% @spec sync_set_anchor(Store, PeerGuid, SeqNum) -> Result
%%       Store = pid()
%%       PeerGuid = guid()
%%       SeqNum = integer()
%%       Result = ok | {error, Reason}
sync_set_anchor(Store, PeerGuid, SeqNum) ->
	call_store(Store, {sync_set_anchor, PeerGuid, SeqNum}).


%% @doc Release the lock for the peer store synchronizing process.
%% @spec sync_finish(Store, PeerGuid) -> ok | {error, Reason}
sync_finish(Store, PeerGuid) ->
	call_store(Store, {sync_finish, PeerGuid}).


hash_revision(#revision{flags=Flags, mtime=Mtime} = Revision) ->
	Parts = Revision#revision.parts,
	BinParts = lists:foldl(
		fun ({FourCC, Hash}, AccIn) ->
			<<AccIn/binary, FourCC/binary, Hash/binary>>
		end,
		<<(length(Parts)):32/little>>,
		Parts),
	BinParents = hash_revision_list(Revision#revision.parents),
	BinType = hash_revision_string(Revision#revision.type),
	BinCreator = hash_revision_string(Revision#revision.creator),
	{SDL, WDL, SRL, WRL, DocMap} = Revision#revision.links,
	BinSDL = hash_revision_list(SDL),
	BinWDL = hash_revision_list(WDL),
	BinSRL = hash_revision_list(SRL),
	BinWRL = hash_revision_list(WRL),
	BinDocMap = lists:foldl(
		fun({Doc, RevList}, Acc) ->
			<<Acc/binary, Doc/binary, (hash_revision_list(RevList))/binary>>
		end,
		<<(length(DocMap)):32/little>>,
		DocMap),
	binary_part(
		crypto:sha(<<Flags:32/little, BinParts/binary, BinParents/binary,
			Mtime:64/little, BinType/binary, BinCreator/binary, BinSDL/binary,
			BinWDL/binary, BinSRL/binary, BinWRL/binary, BinDocMap/binary>>),
		0,
		16).

hash_revision_list(List) ->
	lists:foldl(
		fun (Guid, AccIn) -> <<AccIn/binary, Guid/binary>> end,
		<<(length(List)):32/little>>,
		List).

hash_revision_string(String) ->
	<<(size(String)):32/little, String/binary>>.


call_store(Store, Request) ->
	call_store(Store, Request, {error, enxio}).


call_store(Store, Request, FailReply) ->
	try
		gen_server:call(Store, Request)
	catch
		exit:_ -> FailReply
	end.

