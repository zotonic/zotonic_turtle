%% @copyright 2026 Marc Worrell
%% @doc Deterministic Turtle writer. Uses only the standard Zotonic prefixes.
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

-module(turtle_writer).

-export([
    generate/1
]).

generate(Triples) ->
    Ns = zotonic_rdf:namespaces(),
    Prefixes = [
        [<<"@prefix ">>, P, <<": <">>, escape_iri(U), <<"> .\n">>]
     || {P, U} <- lists:sort(maps:to_list(Ns))
    ],
    Lines = [triple(T) || T <- lists:usort(Triples)],
    iolist_to_binary([Prefixes, $\n, Lines]).

triple(#{<<"graph">> := _}) ->
    throw({turtle, named_graph_not_supported});
triple(#{<<"subject">> := S, <<"predicate">> := P} = T) ->
    case P of
        <<"_:", _/binary>> ->
            throw({turtle, blank_predicate});
        _ ->
            ok
    end,
    [resource(S), $\s, resource(P), $\s, object(T), <<" .\n">>];
triple(_) ->
    throw({turtle, invalid_triple}).

object(#{<<"@id">> := Id}) ->
    resource(Id);
object(#{<<"@value">> := V} = T) ->
    case maps:is_key(<<"@direction">>, T) of
        true ->
            throw({turtle, directional_literal_not_supported});
        false ->
            ok
    end,
    Lex = lexical(V),
    Literal = [$", escape_string(Lex), $"],
    case {maps:find(<<"@language">>, T), maps:find(<<"@type">>, T)} of
        {{ok, Lang}, _} ->
            case re:run(Lang, <<"^[A-Za-z]+(?:-[A-Za-z0-9]+)*$">>, [{capture, none}]) of
                match ->
                    [Literal, $@, Lang];
                _ ->
                    throw({turtle, invalid_language})
            end;
        {_, {ok, <<"@json">>}} ->
            throw({turtle, json_literal_not_supported});
        {_, {ok, <<"_:", _/binary>>}} ->
            throw({turtle, invalid_datatype});
        {_, {ok, Type}} ->
            [Literal, <<"^^">>, resource(Type)];
        _ ->
            Literal
    end;
object(_) ->
    throw({turtle, invalid_object}).

resource(<<"_:", Name/binary>> = Id) ->
    case turtle_lexer:scan(Id) of
        [{blank, _, _}] ->
            Id;
        _ ->
            throw({turtle, {invalid_blank, Name}})
    end;
resource(Uri) when is_binary(Uri) ->
    case rdf_iri:is_absolute(Uri) of
        true ->
            ok;
        _ ->
            throw({turtle, {invalid_iri, Uri}})
    end,
    Compact = zotonic_rdf:ns_compact(Uri),
    case Compact =/= Uri andalso valid_compact(Compact) of
        true ->
            Compact;
        false ->
            [$<, escape_iri(Uri), $>]
    end;
resource(_) ->
    throw({turtle, invalid_resource}).

valid_compact(Compact) ->
    try
        case turtle_lexer:scan(Compact) of
            [{pname, _, _, _}] ->
                true;
            _ ->
                false
        end
    catch
        throw:_ ->
            false
    end.

lexical(V) when is_binary(V) ->
    V;
lexical(V) when is_integer(V) ->
    integer_to_binary(V);
lexical(V) when is_float(V) ->
    float_to_binary(V, [short]);
lexical(true) ->
    <<"true">>;
lexical(false) ->
    <<"false">>;
lexical(_) ->
    throw({turtle, invalid_literal}).

escape_string(B) ->
    escape(B, string).

escape_iri(B) ->
    escape(B, iri).

escape(B, Kind) ->
    case unicode:characters_to_list(B) of
        Cs when is_list(Cs) ->
            [escaped(C, Kind) || C <- Cs];
        _ ->
            throw({turtle, invalid_utf8})
    end.

escaped($", string) ->
    <<"\\\"">>;
escaped($\\, string) ->
    <<"\\\\">>;
escaped($\n, string) ->
    <<"\\n">>;
escaped($\r, string) ->
    <<"\\r">>;
escaped($\t, string) ->
    <<"\\t">>;
escaped(C, Kind) ->
    case C < 32 orelse C =:= 127 orelse (Kind =:= iri andalso lists:member(C, " <>\"{}|^`\\")) of
        true ->
            io_lib:format("\\u~4.16.0B", [C]);
        false ->
            unicode:characters_to_binary([C])
    end.
