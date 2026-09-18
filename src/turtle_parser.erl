%% @copyright 2026 Marc Worrell
%% @doc Recursive-descent RDF 1.1 Turtle parser.
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

-module(turtle_parser).

-export([
    parse/2
]).

-include_lib("zotonic_rdf/include/zotonic_rdf.hrl").

parse(Tokens, Options) ->
    Used = maps:from_list([{Id, true} || {blank, Id, _} <- Tokens]),
    S = #{
        namespaces => maps:get(prefixes, Options, #{}),
        base => maps:get(base, Options, undefined),
        used => Used,
        triples => [],
        depth => 0,
        max_depth => maps:get(max_depth, Options, 128)
    },
    Final = document(Tokens, S),
    lists:usort(maps:get(triples, Final)).

document([], S) ->
    S;
document([{Kind, _}, {pname, Prefix, <<>>, _}, {iri, Uri, _} | Rest], S) when
    Kind =:= prefix; Kind =:= sparql_prefix
->
    Iri = absolute(Uri, S),
    Ns = maps:get(namespaces, S),
    document(directive_end(Kind, Rest), S#{namespaces => Ns#{Prefix => Iri}});
document([{Kind, _}, {iri, Uri, _} | Rest], S) when Kind =:= base; Kind =:= sparql_base ->
    document(directive_end(Kind, Rest), S#{base => absolute(Uri, S)});
document(Tokens, S0) ->
    {Subject, Rest, S1} = resource(Tokens, S0),
    {Rest1, S2} =
        case Rest of
            [{$., _} | _] ->
                % A nonempty blank-node property list can stand alone.
                case Tokens of
                    [{$[, _}, {$], _} | _] ->
                        fail(Rest, expected_predicate);
                    [{$[, _} | _] ->
                        {Rest, S1};
                    _ ->
                        fail(Rest, expected_predicate)
                end;
            _ ->
                predicates(Subject, Rest, S1)
        end,
    document(expect($., Rest1), S2).

directive_end(prefix, T) ->
    expect($., T);
directive_end(base, T) ->
    expect($., T);
directive_end(_, T) ->
    T.

predicates(Subject, Tokens, S0) ->
    {Predicate, Rest, S1} = predicate(Tokens, S0),
    {Rest1, S2} = objects(Subject, Predicate, Rest, S1),
    predicate_tail(Subject, Rest1, S2).

predicate_tail(Subject, [{$;, _} | Rest], S) ->
    case Rest of
        [{$;, _} | _] ->
            predicate_tail(Subject, Rest, S);
        [{$., _} | _] ->
            {Rest, S};
        [{$], _} | _] ->
            {Rest, S};
        [] ->
            {Rest, S};
        _ ->
            predicates(Subject, Rest, S)
    end;
predicate_tail(_, Rest, S) ->
    {Rest, S}.

predicate([{a, _} | T], S) ->
    {<<?NS_RDF/binary, "type">>, T, S};
predicate([{iri, Uri, _} | T], S) ->
    {absolute(Uri, S), T, S};
predicate([{pname, P, L, Line} | T], S) ->
    {prefixed(P, L, Line, S), T, S};
predicate(T, _) ->
    fail(T, expected_predicate).

objects(Subject, P, Tokens, S0) ->
    {O, Rest, S1} = object(Tokens, S0),
    S2 = emit(Subject, P, O, S1),
    case Rest of
        [{$,, _} | T] ->
            objects(Subject, P, T, S2);
        _ ->
            {Rest, S2}
    end.

object([{string, V, _}, {language, Lang, _} | Rest], S) ->
    {#{<<"@value">> => V, <<"@language">> => Lang}, Rest, S};
object([{string, V, _}, {'^^', _} | Rest], S0) ->
    {Type, T, S} = predicate_iri(Rest, S0),
    {#{<<"@value">> => V, <<"@type">> => Type}, T, S};
object([{string, V, _} | Rest], S) ->
    {#{<<"@value">> => V, <<"@type">> => <<?NS_XSD/binary, "string">>}, Rest, S};
object([{number, V, _} | Rest], S) ->
    Type = case binary:match(V, [<<"e">>, <<"E">>]) of
        nomatch ->
            case binary:match(V, <<".">>) of
                nomatch ->
                    <<"integer">>;
                _ ->
                    <<"decimal">>
            end;
        _ ->
            <<"double">>
    end,
    {#{<<"@value">> => V, <<"@type">> => <<?NS_XSD/binary, Type/binary>>}, Rest, S};
object([{boolean, V, _} | Rest], S) ->
    {#{<<"@value">> => V, <<"@type">> => <<?NS_XSD/binary, "boolean">>}, Rest, S};
object(Tokens, S0) ->
    {Id, Rest, S} = resource(Tokens, S0),
    {#{<<"@id">> => Id}, Rest, S}.

predicate_iri([{iri, _, _} | _] = T, S) ->
    predicate(T, S);
predicate_iri([{pname, _, _, _} | _] = T, S) ->
    predicate(T, S);
predicate_iri(T, _) ->
    fail(T, expected_datatype_iri).

resource([{iri, Uri, _} | Rest], S) ->
    {absolute(Uri, S), Rest, S};
resource([{pname, P, L, Line} | Rest], S) ->
    {prefixed(P, L, Line, S), Rest, S};
resource([{blank, Id, _} | Rest], S) ->
    {Id, Rest, S};
resource([{$[, _}, {$], _} | Rest], S0) ->
    {Id, S} = blank(S0),
    {Id, Rest, S};
resource([{$[, Line} | Rest], S0) ->
    S1 = enter(Line, S0),
    {Id, S2} = blank(S1),
    {Tail, S3} = predicates(Id, Rest, S2),
    {Id, expect($], Tail), leave(S3)};
resource([{$(, Line} | Rest], S0) ->
    {Id, T, S} = collection(Rest, enter(Line, S0)),
    {Id, T, leave(S)};
resource(T, _) ->
    fail(T, expected_resource).

collection([{$), _} | Rest], S) ->
    {<<?NS_RDF/binary, "nil">>, Rest, S};
collection(Tokens, S0) ->
    {Id, S1} = blank(S0),
    {First, Rest, S2} = object(Tokens, S1),
    {Next, Tail, S3} = collection(Rest, S2),
    S4 = emit(Id, <<?NS_RDF/binary, "first">>, First, S3),
    {Id, Tail, emit(Id, <<?NS_RDF/binary, "rest">>, #{<<"@id">> => Next}, S4)}.

blank(S) ->
    Id = zotonic_rdf:blank_id(),
    Used = maps:get(used, S),
    case maps:is_key(Id, Used) of
        true ->
            blank(S);
        false ->
            {Id, S#{used => Used#{Id => true}}}
    end.

emit(Subject, P, O, S) ->
    S#{triples => [O#{<<"subject">> => Subject, <<"predicate">> => P} | maps:get(triples, S)]}.

absolute(Uri, S) ->
    Resolved = jsonld_context:resolve(Uri, maps:get(base, S)),
    case rdf_iri:is_absolute(Resolved) of
        true ->
            Resolved;
        _ ->
            throw({turtle, #{reason => {relative_iri_without_base, Uri}}})
    end.

prefixed(P, Local, Line, S) ->
    case maps:find(P, maps:get(namespaces, S)) of
        {ok, Ns} ->
            <<Ns/binary, Local/binary>>;
        error ->
            throw({turtle, #{line => Line, reason => {undefined_prefix, P}}})
    end.

enter(Line, S) ->
    Depth = maps:get(depth, S) + 1,
    case Depth =< maps:get(max_depth, S) of
        true ->
            S#{depth => Depth};
        false ->
            throw({turtle, #{line => Line, reason => depth_exceeded}})
    end.

leave(S) ->
    S#{depth => maps:get(depth, S) - 1}.

expect(Char, [{Char, _} | Rest]) ->
    Rest;
expect(Char, T) ->
    fail(T, {expected, Char}).

fail([], Reason) ->
    throw({turtle, #{reason => Reason, at => eof}});
fail([Token | _], Reason) ->
    throw({turtle, #{line => element(tuple_size(Token), Token), reason => Reason}}).
