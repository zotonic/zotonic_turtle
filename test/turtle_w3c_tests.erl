%% @copyright 2026 Marc Worrell
%% Vendored W3C RDF 1.1 Turtle syntax, graph evaluation and writer tests.
%% Fixtures: https://github.com/w3c/rdf-tests/tree/main/rdf/rdf11/rdf-turtle
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

-module(turtle_w3c_tests).

-include_lib("eunit/include/eunit.hrl").
-define(BASE, <<"https://w3c.github.io/rdf-tests/rdf/rdf11/rdf-turtle/">>).
-define(MF, <<"http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#">>).

syntax_test_() ->
    case os:getenv("W3C_TURTLE_TESTS") of
        false ->
            tests(default_root());
        Root ->
            tests(Root)
    end.

tests(Root) ->
    {ok, Manifest} = file:read_file(filename:join(Root, "manifest.ttl")),
    {ok, Triples} = zotonic_turtle:parse_triples(Manifest, #{base => ?BASE}),
    Docs = rdf_document:from_triples(Triples),
    [
        {binary_to_list(maps:get(<<"@id">>, D)), fun() ->
            check(Root, D)
        end}
     || D <- Docs, maps:is_key(<<?MF/binary, "action">>, D)
    ].

default_root() ->
    Candidates = [
        filename:join(filename:dirname(?FILE), "data/w3c-turtle"),
        filename:join(filename:dirname(code:which(?MODULE)), "data/w3c-turtle")
    ],
    case [P || P <- Candidates, filelib:is_file(filename:join(P, "manifest.ttl"))] of
        [Root | _] ->
            Root;
        [] ->
            error(missing_w3c_turtle_fixtures)
    end.

check(Root, Doc) ->
    [Type] = maps:get(<<"@type">>, Doc),
    [#{<<"@id">> := Url}] = maps:get(<<?MF/binary, "action">>, Doc),
    Base = ?BASE,
    Size = byte_size(Base),
    <<Base:Size/binary, Path/binary>> = Url,
    {ok, Input} = file:read_file(filename:join(Root, binary_to_list(Path))),
    Result = zotonic_turtle:parse_triples(Input, #{base => Url}),
    case binary:match(Type, <<"Negative">>) of
        nomatch ->
            ?assertMatch({ok, _}, Result),
            {ok, Triples} = Result,
            {ok, Encoded} = zotonic_turtle:generate_triples(Triples),
            ?assertEqual({ok, Triples}, zotonic_turtle:parse_triples(Encoded)),
            case maps:find(<<?MF/binary, "result">>, Doc) of
                {ok, [#{<<"@id">> := ExpectedUrl}]} ->
                    <<Base:Size/binary, ExpectedPath/binary>> = ExpectedUrl,
                    {ok, ExpectedInput} = file:read_file(
                        filename:join(Root, binary_to_list(ExpectedPath))
                    ),
                    {ok, Expected} = zotonic_turtle:parse_triples(ExpectedInput, #{
                        base => ExpectedUrl
                    }),
                    ?assert(graph_equal(Triples, Expected));
                error ->
                    ok
            end;
        _ ->
            ?assertMatch({error, _}, Result)
    end.

%% Compare RDF graphs modulo blank-node names. Degree signatures narrow the
%% candidates, then each partial assignment checks fully mapped triples.

graph_equal(A, B) ->
    AB = blanks(A),
    BB = blanks(B),
    Candidates = [{X, [Y || Y <- BB, signature(X, A) =:= signature(Y, B)]} || X <- AB],
    Ordered = lists:sort(
        fun({_, Xs}, {_, Ys}) ->
            length(Xs) =< length(Ys)
        end,
        Candidates
    ),
    length(A) =:= length(B) andalso length(AB) =:= length(BB) andalso
        assign(Ordered, #{}, A, maps:from_keys(B, true)).

blanks(Ts) ->
    lists:usort([
        V
     || T <- Ts,
        {K, V} <- maps:to_list(T),
        (K =:= <<"subject">> orelse K =:= <<"@id">>),
        is_blank(V)
    ]).

is_blank(<<"_:", _/binary>>) ->
    true;
is_blank(_) ->
    false.

signature(Id, Ts) ->
    lists:sort([
        maps:map(
            fun(K, V) ->
                case K =:= <<"subject">> orelse K =:= <<"@id">> of
                    true when V =:= Id ->
                        self;
                    true ->
                        case is_blank(V) of
                            true ->
                                blank;
                            false ->
                                V
                        end;
                    false ->
                        V
                end
            end,
            T
        )
     || T <- Ts, maps:get(<<"subject">>, T) =:= Id orelse maps:get(<<"@id">>, T, undefined) =:= Id
    ]).

assign([], Mapping, Ts, Expected) ->
    compatible(Mapping, Ts, Expected);
assign([{Id, Choices} | Rest], Mapping, Ts, Expected) ->
    lists:any(
        fun(Choice) ->
            Next = Mapping#{Id => Choice},
            not lists:member(Choice, maps:values(Mapping)) andalso
                compatible(Next, Ts, Expected) andalso assign(Rest, Next, Ts, Expected)
        end,
        Choices
    ).

compatible(Mapping, Ts, Expected) ->
    lists:all(
        fun(T) ->
            Bs = blanks([T]),
            case
                lists:all(
                    fun(B) ->
                        maps:is_key(B, Mapping)
                    end,
                    Bs
                )
            of
                false ->
                    true;
                true ->
                    Mapped = maps:map(
                        fun(K, V) ->
                            case K =:= <<"subject">> orelse K =:= <<"@id">> of
                                true ->
                                    maps:get(V, Mapping, V);
                                false ->
                                    V
                            end
                        end,
                        T
                    ),
                    maps:is_key(Mapped, Expected)
            end
        end,
        Ts
    ).
