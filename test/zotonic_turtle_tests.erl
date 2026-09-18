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

-module(zotonic_turtle_tests).

-include_lib("eunit/include/eunit.hrl").

prefix_base_literals_test() ->
    Turtle = <<
        "@base <https://example.test/> .\n@prefix s: <https://schema.org/> .\n"
        "<alice> a s:Person ; s:name \"Alice\"@EN ; s:age 42 ; s:score 1.5, 1e2 ; s:active true ."
    >>,
    {ok, Ts} = zotonic_turtle:parse_triples(Turtle),
    ?assertEqual(6, length(Ts)),
    {ok, [D]} = zotonic_turtle:parse(Turtle),
    ?assertEqual(<<"schema:Person">>, maps:get(<<"@type">>, D)),
    ?assertEqual(<<"https://example.test/alice">>, maps:get(<<"@id">>, D)),
    {ok, Generated} = zotonic_turtle:generate(D),
    ?assertEqual({ok, Ts}, zotonic_turtle:parse_triples(Generated)),
    ?assertNotEqual(nomatch, binary:match(Generated, <<"@prefix zotonic:">>)).

blank_cycles_and_collection_test() ->
    {ok, Docs} = zotonic_turtle:parse(<<
        "@prefix ex: <https://example.test/> . "
        "_:a ex:next _:b . _:b ex:next _:a . ex:s ex:list (1 [ex:name \"x\"]) ."
    >>),
    ?assert(length(Docs) >= 5),
    {ok, Out} = zotonic_turtle:generate(Docs),
    ?assertEqual({ok, Docs}, zotonic_turtle:parse(Out)).

unicode_and_escapes_test() ->
    {ok, [D]} = zotonic_turtle:parse(<<
        "PREFIX s: <https://schema.org/>\n"
        "<https://example.test/a> s:name '''line\n\\u00E9\\U0001F600''' ."
    >>),
    ?assertEqual(
        #{<<"@value">> => <<"line\né😀"/utf8>>, <<"@type">> => <<"xsd:string">>},
        maps:get(<<"schema:name">>, D)
    ),
    {ok, Out} = zotonic_turtle:generate(D),
    ?assertEqual({ok, [D]}, zotonic_turtle:parse(Out)).

invalid_input_test() ->
    lists:foreach(
        fun(T) ->
            ?assertMatch({error, _}, zotonic_turtle:parse(T))
        end,
        [
            <<"ex:s ex:p ex:o .">>,
            <<"<relative> <https://ex/p> 1 .">>,
            <<"<https://ex/s> <https://ex/p> \"bad\\q\" .">>,
            <<"<https://ex/s> <https://ex/p> \"bad\\uD800\" .">>,
            <<"<https://ex/s> <https://ex/p> \"unterminated">>,
            <<"<https://ex/s> <https://ex/p> [ .">>,
            <<"<https://ex/s> <https://ex/p> 1">>
        ]
    ).

cross_format_test() ->
    Json = <<
        "{\"@context\": {\"name\": \"https://schema.org/name\"},"
        "\"@id\": \"https://example.test/alice\", \"name\": \"Alice\"}"
    >>,
    {ok, Docs} = zotonic_jsonld:parse(Json),
    {ok, Turtle} = zotonic_turtle:generate(Docs),
    {ok, FromTurtle} = zotonic_turtle:parse(Turtle),
    {ok, JsonOut} = zotonic_jsonld:generate(FromTurtle),
    ?assertEqual(zotonic_jsonld:to_triples(Docs), zotonic_jsonld:to_triples(JsonOut)).

unicode_names_and_negative_names_test() ->
    Name = unicode:characters_to_binary([16#200c, 16#203f]),
    Input =
        <<"@prefix ", Name/binary, ": <https://example.test/> . ", Name/binary, ":s ", Name/binary,
            ":p ", Name/binary, ":o .">>,
    {ok, Ts} = zotonic_turtle:parse_triples(Input),
    {ok, Output} = zotonic_turtle:generate_triples(Ts),
    ?assertEqual({ok, Ts}, zotonic_turtle:parse_triples(Output)),
    ?assertMatch({error, _}, zotonic_turtle:parse(<<"[] .">>)),
    ?assertMatch(
        {error, _}, zotonic_turtle:parse(<<"@prefix : <https://example.test/> . :s :p :-bad .">>)
    ).

external_context_loading_policy_test() ->
    Url = <<"https://example.test/context">>,
    Input = #{
        <<"@context">> => Url,
        <<"@id">> => <<"https://example.test/alice">>,
        <<"name">> => <<"Alice">>
    },
    ForbiddenLoader = fun(_) ->
        error(external_loader_must_not_be_called)
    end,
    Expected = {error, {external_context_loading_disabled, Url}},
    ?assertEqual(Expected, zotonic_turtle:generate(Input)),
    ?assertEqual(Expected, zotonic_turtle:generate(Input, #{document_loader => ForbiddenLoader})),
    ?assertEqual(
        Expected,
        zotonic_turtle:generate(Input, #{
            allow_external_contexts => false,
            document_loader => ForbiddenLoader
        })
    ),
    Loader = fun(RequestedUrl) ->
        ?assertEqual(Url, RequestedUrl),
        {ok, #{<<"@context">> => #{<<"name">> => <<"https://schema.org/name">>}}}
    end,
    ?assertMatch(
        {ok, _},
        zotonic_turtle:generate(Input, #{
            allow_external_contexts => true,
            document_loader => Loader
        })
    ),
    %% Prefix/base directives and file IRIs are identifiers, never fetch requests.
    Turtle = <<
        "@base <file:///tmp/> . @prefix ex: <https://example.test/> . "
        "<s> ex:p <o> ."
    >>,
    ?assertMatch({ok, _}, zotonic_turtle:parse(Turtle, #{document_loader => ForbiddenLoader})).
