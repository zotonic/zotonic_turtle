%% @copyright 2026 Marc Worrell
%% @doc UTF-8 Turtle lexer with line-numbered tokens and strict escapes.
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

-module(turtle_lexer).

-export([
    scan/1
]).

scan(Binary) ->
    case unicode:characters_to_list(Binary) of
        L when is_list(L) ->
            tokens(L, 1, []);
        _ ->
            fail(1, invalid_utf8)
    end.

tokens([], _, Acc) ->
    lists:reverse(Acc);
tokens([$\s | T], L, A) ->
    tokens(T, L, A);
tokens([$\t | T], L, A) ->
    tokens(T, L, A);
tokens([$\r | T], L, A) ->
    tokens(T, L, A);
tokens([$\n | T], L, A) ->
    tokens(T, L + 1, A);
tokens([$# | T], L, A) ->
    tokens(comment(T), L, A);
tokens([$< | T], L, A) ->
    {Value, Rest, Line} = iri(T, L, []),
    tokens(Rest, Line, [{iri, Value, L} | A]);
tokens([Q, Q, Q | T], L, A) when Q =:= $"; Q =:= $' ->
    {Value, Rest, Line} = string(T, Q, true, L, []),
    tokens(Rest, Line, [{string, Value, L} | A]);
tokens([Q | T], L, A) when Q =:= $"; Q =:= $' ->
    {Value, Rest, Line} = string(T, Q, false, L, []),
    tokens(Rest, Line, [{string, Value, L} | A]);
tokens([$^, $^ | T], L, A) ->
    tokens(T, L, [{'^^', L} | A]);
tokens([C | T], L, A) when C =:= $;; C =:= $,; C =:= $[; C =:= $]; C =:= $(; C =:= $) ->
    tokens(T, L, [{C, L} | A]);
tokens([C | _] = Chars, L, A) when C >= $0, C =< $9; C =:= $+; C =:= $-; C =:= $. ->
    B = unicode:characters_to_binary(Chars),
    Pattern =
        <<"^[+-]?(?:(?:[0-9]+\\.[0-9]*|\\.[0-9]+|[0-9]+)[eE][+-]?[0-9]+|[0-9]*\\.[0-9]+|[0-9]+)">>,
    case re:run(B, Pattern, [{capture, first, binary}]) of
        {match, [N]} ->
            Rest = binary:part(B, byte_size(N), byte_size(B) - byte_size(N)),
            tokens(unicode:characters_to_list(Rest), L, [{number, N, L} | A]);
        nomatch when C =:= $. ->
            tokens(tl(Chars), L, [{$., L} | A]);
        nomatch ->
            fail(L, invalid_number)
    end;
tokens(Chars, L, A) ->
    {Raw, Rest} = word(Chars, []),
    case Raw of
        [] ->
            fail(L, unexpected_character);
        _ ->
            ok
    end,
    {Trimmed, Dots} = trim_dots(lists:reverse(Raw), 0),
    case Trimmed of
        [] ->
            fail(L, invalid_name);
        _ ->
            ok
    end,
    Value = unicode:characters_to_binary(lists:reverse(Trimmed)),
    Token = word_token(Value, L),
    tokens(Rest, L, lists:duplicate(Dots, {$., L}) ++ [Token | A]).

comment([]) ->
    [];
comment([$\n | _] = T) ->
    T;
comment([_ | T]) ->
    comment(T).

word([], A) ->
    {lists:reverse(A), []};
word([$\\, C | T], A) ->
    word(T, [C, $\\ | A]);
word([C | _] = T, A) when
    C =:= $\s;
    C =:= $\t;
    C =:= $\r;
    C =:= $\n;
    C =:= $#;
    C =:= $<;
    C =:= $>;
    C =:= $";
    C =:= $';
    C =:= $;;
    C =:= $,;
    C =:= $[;
    C =:= $];
    C =:= $(;
    C =:= $);
    C =:= $^
->
    {lists:reverse(A), T};
word([C | T], A) ->
    word(T, [C | A]).

trim_dots([$., $\\ | _] = R, N) ->
    {R, N};
trim_dots([$. | T], N) ->
    trim_dots(T, N + 1);
trim_dots(R, N) ->
    {R, N}.

word_token(<<"@prefix">>, L) ->
    {prefix, L};
word_token(<<"@base">>, L) ->
    {base, L};
word_token(<<"a">>, L) ->
    {a, L};
word_token(<<"true">> = V, L) ->
    {boolean, V, L};
word_token(<<"false">> = V, L) ->
    {boolean, V, L};
word_token(<<"@", Tag/binary>>, L) ->
    check(
        re:run(Tag, <<"^[A-Za-z]+(?:-[A-Za-z0-9]+)*$">>, [{capture, none}]) =:= match,
        L,
        invalid_language
    ),
    {language, unicode:characters_to_binary(string:lowercase(binary_to_list(Tag))), L};
word_token(<<"_:", Name/binary>>, L) ->
    check(valid_blank(Name), L, invalid_blank_node),
    {blank, <<"_:", Name/binary>>, L};
word_token(V, L) ->
    case string:uppercase(binary_to_list(V)) of
        "PREFIX" ->
            {sparql_prefix, L};
        "BASE" ->
            {sparql_base, L};
        _ ->
            case binary:split(V, <<":">>) of
                [Prefix, Local] ->
                    check(valid_prefix(Prefix), L, invalid_prefix),
                    {pname, Prefix, local(unicode:characters_to_list(Local), L, []), L};
                _ ->
                    fail(L, {invalid_token, V})
            end
    end.

valid_prefix(<<>>) ->
    true;
valid_prefix(B) ->
    case unicode:characters_to_list(B) of
        [H | T] ->
            pn_base(H) andalso
                lists:all(
                    fun(C) ->
                        pn_char(C) orelse C =:= $.
                    end,
                    T
                ) andalso lists:last([H | T]) =/= $.;
        _ ->
            false
    end.

valid_blank(B) ->
    case unicode:characters_to_list(B) of
        [H | T] ->
            (pn_u(H) orelse digit(H)) andalso
                lists:all(
                    fun(C) ->
                        pn_char(C) orelse C =:= $.
                    end,
                    T
                ) andalso lists:last([H | T]) =/= $.;
        _ ->
            false
    end.

pn_base(C) ->
    (C >= $A andalso C =< $Z) orelse (C >= $a andalso C =< $z) orelse
        lists:any(
            fun({A, B}) ->
                C >= A andalso C =< B
            end,
            [
                {16#c0, 16#d6},
                {16#d8, 16#f6},
                {16#f8, 16#2ff},
                {16#370, 16#37d},
                {16#37f, 16#1fff},
                {16#200c, 16#200d},
                {16#2070, 16#218f},
                {16#2c00, 16#2fef},
                {16#3001, 16#d7ff},
                {16#f900, 16#fdcf},
                {16#fdf0, 16#fffd},
                {16#10000, 16#effff}
            ]
        ).

pn_u(C) ->
    C =:= $_ orelse pn_base(C).

digit(C) ->
    C >= $0 andalso C =< $9.

pn_char(C) ->
    pn_u(C) orelse digit(C) orelse C =:= $- orelse C =:= 16#b7 orelse
        (C >= 16#300 andalso C =< 16#36f) orelse (C >= 16#203f andalso C =< 16#2040).

local([], _, A) ->
    unicode:characters_to_binary(lists:reverse(A));
local([$\\, C | T], L, A) ->
    check(lists:member(C, "_~.-!$&'()*+,;=/?#@%"), L, invalid_local_escape),
    local(T, L, [C | A]);
local([$%, A, B | T], L, Acc) ->
    check(hex(A) andalso hex(B), L, invalid_percent_escape),
    local(T, L, [B, A, $% | Acc]);
local([C | T], L, A) ->
    Valid = case A of
        [] ->
            pn_u(C) orelse digit(C) orelse C =:= $:;
        _ ->
            pn_char(C) orelse C =:= $. orelse C =:= $:
    end,
    check(Valid, L, invalid_local_name),
    local(T, L, [C | A]).

iri([], L, _) ->
    fail(L, unterminated_iri);
iri([$> | T], L, A) ->
    {unicode:characters_to_binary(lists:reverse(A)), T, L};
iri([$\\, C | T], L, A) when C =:= $u; C =:= $U ->
    {Code, Rest} = unicode_escape(C, T, L),
    iri(Rest, L, [Code | A]);
iri([C | T], L, A) ->
    check(C > 32 andalso not lists:member(C, "<>\"{}|^`\\"), L, invalid_iri_character),
    iri(T, L, [C | A]).

string([], _, _, L, _) ->
    fail(L, unterminated_string);
string([Q, Q, Q | T], Q, true, L, A) ->
    {unicode:characters_to_binary(lists:reverse(A)), T, L};
string([Q | T], Q, false, L, A) ->
    {unicode:characters_to_binary(lists:reverse(A)), T, L};
string([$\\, C | T], Q, Long, L, A) ->
    {Code, Rest} = escape(C, T, L),
    string(Rest, Q, Long, L, [Code | A]);
string([C | T], Q, Long, L, A) ->
    check(Long orelse (C =/= $\n andalso C =/= $\r), L, newline_in_short_string),
    Line = case C of
        $\n ->
            L + 1;
        _ ->
            L
    end,
    string(T, Q, Long, Line, [C | A]).

escape($u, T, L) ->
    unicode_escape($u, T, L);
escape($U, T, L) ->
    unicode_escape($U, T, L);
escape(C, T, L) ->
    case
        lists:keyfind(C, 1, [
            {$t, $\t}, {$b, 8}, {$n, $\n}, {$r, $\r}, {$f, 12}, {$", $"}, {$', $'}, {$\\, $\\}
        ])
    of
        {_, V} ->
            {V, T};
        false ->
            fail(L, invalid_string_escape)
    end.

unicode_escape(C, T, L) ->
    N = case C of
        $u ->
            4;
        $U ->
            8
    end,
    check(length(lists:sublist(T, N)) =:= N, L, invalid_unicode_escape),
    {Digits, Rest} = lists:split(N, T),
    check(lists:all(fun hex/1, Digits), L, invalid_unicode_escape),
    V = list_to_integer(Digits, 16),
    check(
        V =< 16#10ffff andalso not (V >= 16#d800 andalso V =< 16#dfff), L, invalid_unicode_scalar
    ),
    {V, Rest}.

hex(C) ->
    (C >= $0 andalso C =< $9) orelse (C >= $a andalso C =< $f) orelse (C >= $A andalso C =< $F).

check(true, _, _) ->
    ok;
check(false, L, E) ->
    fail(L, E).

fail(L, E) ->
    throw({turtle, #{line => L, reason => E}}).
