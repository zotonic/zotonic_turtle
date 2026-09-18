%% @copyright 2026 Marc Worrell
%% @end

%% Copyright 2026 Marc Worrell
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(zotonic_turtle).

-moduledoc("Parse and generate RDF 1.1 Turtle using Zotonic RDF documents and standard prefixes.").

-export([
    parse/1,
    parse/2,
    parse_triples/1,
    parse_triples/2,
    generate/1,
    generate/2,
    generate_triples/1,
    decode/1,
    encode/1
]).

-spec parse(Input) -> {ok, [map()]} | {error, term()}
    when
        Input :: iodata().
parse(Input) ->
    parse(Input, #{}).

-spec parse(Input, Options) -> {ok, [map()]} | {error, term()}
    when
        Input :: iodata(),
        Options :: map().
parse(Input, Options) ->
    case parse_triples(Input, Options) of
        {ok, Triples} ->
            protect(fun() ->
                rdf_document:compact(rdf_document:from_triples(Triples))
            end);
        Error ->
            Error
    end.

-spec parse_triples(Input) -> {ok, [map()]} | {error, term()}
    when
        Input :: iodata().
parse_triples(Input) ->
    parse_triples(Input, #{}).

-spec parse_triples(Input, Options) -> {ok, [map()]} | {error, term()}
    when
        Input :: iodata(),
        Options :: map().
parse_triples(Input, Options) ->
    protect(fun() ->
        turtle_parser:parse(turtle_lexer:scan(iolist_to_binary(Input)), Options)
    end).

-spec generate(Documents) -> {ok, binary()} | {error, term()}
    when
        Documents :: map() | [map()].
generate(Documents) ->
    generate(Documents, #{}).

-spec generate(Documents, Options) -> {ok, binary()} | {error, term()}
    when
        Documents :: term(),
        Options :: map().
generate(Documents, Options) ->
    case zotonic_jsonld:to_triples(Documents, Options) of
        {ok, Triples} ->
            generate_triples(Triples);
        Error ->
            Error
    end.

-spec generate_triples(Triples) -> {ok, binary()} | {error, term()}
    when
        Triples :: [map()].
generate_triples(Triples) ->
    protect(fun() ->
        turtle_writer:generate(Triples)
    end).

-spec decode(Input) -> {ok, [map()]} | {error, term()}
    when
        Input :: iodata().
decode(Input) ->
    parse(Input).

-spec encode(Input) -> {ok, binary()} | {error, term()}
    when
        Input :: term().
encode(Input) ->
    generate(Input).

protect(F) ->
    try
        {ok, F()}
    catch
        throw:{turtle, E} ->
            {error, E};
        throw:{jsonld, E} ->
            {error, E};
        throw:{rdf, E} ->
            {error, E};
        error:badarg ->
            {error, invalid_input}
    end.
