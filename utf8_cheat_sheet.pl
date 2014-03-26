#!/usr/bin/perl

use Modern::Perl;
use lib::abs ('/www/srs/lib');
use Data::Dumper;
use Carp;
use JSON::XS;
use Test::More;

use SRS::Utils qw( utf8_to_cp1251 );

=pod

    Запись чисел в разных системах счисления
        0xFF     => 255   - 16-и ричная запись
        0377     => 255   - восмеричная запись
        0b101010 => 42    - двоичная запись

    Схема преобразования символов в коды utf8:
        Первый байт содержит количество байтов символа, закодированное в единичной системе счисления;
        2 - 11
        3 - 111
        ...
        «0» — бит терминатор, означающий завершение кода размера
        далее идут значащие байты кода, которые имеют вид (10xx xxxx), где «10» — биты признака продолжения, а x — значащие биты.

        Пример для 2-ух байтового символа:
        (2 байта) 110x xxxx 10xx xxxx

=cut

my $one_byte_chr_seq;
my $many_byte_chr_seq;
my $string;
my $string_u;
my $num_octets;


say "--------------- use utf8;";

# По умолчанию perl принимает символ 鸡 за набор байт и работает с ним как с бинарными данными
$one_byte_chr_seq = "鸡\n";
is( ( join ".", map { ord } split //, $one_byte_chr_seq ), "233.184.161.10",
    "По умолчанию перл понимает unicode символы как набор бинарных данных"
);

# В зоне действия 'use utf8' он уже распознается как символ и perl работает со строкой
# состоящей из двух символов: [ 鸡 \n ]
{
    use utf8;

    $many_byte_chr_seq = "鸡\n";
}

is( ( join ".", map { ord } split //, $many_byte_chr_seq ), "40481.10",
    "С включеной прагмой 'use utf8;' перл понимает unicode символы как набор числовых кодов Unicode"
);

# Можно использовать no utf8 если хотим что бы perl воспринял текст как байты
{
    use utf8;
    no utf8;

    $one_byte_chr_seq = "鸡\n";
}

is( ( join ".", map { ord } split //, $one_byte_chr_seq ), "233.184.161.10",
    "Можно использовать 'no utf8;' если хотим что бы perl воспринял текст как байты"
);


say "--------------- use bytes;";

# Сохраним строку из двух символов, perl будет работать с такими данными как со строкой
# chr(127) - последний возможный символ в ASCII-7 bit.
# Он одинаков для ASCII и UTF-8.
$many_byte_chr_seq = chr(400) . chr(127);

# Напечатаем коды символов
is( length $many_byte_chr_seq, 2, "Длина строки 2 символа" );
is( sprintf( "%vd", $many_byte_chr_seq ), "400.127",
    "Строка содержит числовые коды символов Unicode: 400.127"
);
{
    use utf8 ();
    ok( utf8::is_utf8($many_byte_chr_seq), 'Флаг установлен' );
}

{
    # Если сделать так, то данные будут восприниматься как бинарные
    use bytes; # or "require bytes; bytes::length()"

    $one_byte_chr_seq = $many_byte_chr_seq;

    # Напечатаем набор байтов соответствующий строке.
    # Первым символ кодируется двумя байтам, т.к. > 127, а второй одним.
    is( length $one_byte_chr_seq, 3, "Последовательность байтов длиной 3 байта" );
    is( sprintf( "%vd", $one_byte_chr_seq ), "198.144.127",
        "Бинарные данные содержащие закодированные utf8 символы 198.144.127"
    );
}


say "--------------- print character sequence";

# Теперь попробуем напечатать utf8 строку в консоль, которая использует utf8
# но т.к. perl по умолчанию думает что все потоки вывода работают в одно байтной
# кодировке, то он выведет варнинг: "Wide character in print at", т.к. наша строка
# содержит символы из двух байт.
# Поэтому нужно сказать перлу что поток вывода понимает utf8
{
    binmode( STDOUT, ':utf8' );
    say $many_byte_chr_seq;
    # Скажем перлу что поток вывода имеет стандарный формат
    binmode( STDOUT );
}


say "--------------- string context";

# Строка с элеметнами 127 < X <= 255, используемая в символьном контексте интерпретируется как
# последовательность Unicde символов от 127 до 255, этот диапазон в Unicode занят символами Latin1.
# Это, в частности, означает, что строка с не-ASCII байтами, без utf-8 флага,
# интерпретируется как строка в кодировке Latin1
# Например кирилическая прописная "Т" в cp1251 это равно байту 210
# а в строковом контексте этот байт будет воспринят как unicode,
# что соответствует байту 0xD2 т.е. символу "Ò"
{
    use utf8;
    use Encode (qw/ encode decode /);

    $string = utf8_to_cp1251('Тест');

    is( $string, 'Òåñò', encode( 'UTF-8', 'Строка с элеметнами 127 < X <= 255, используемая в символьном контексте интерпретируется как последовательность Unicode символов от 127 до 255, этот диапазон в Unicode занят символами Latin1' ) );
}

say "--------------- functions tests";

# Если где-то есть код, который ожидает бинарные данные, он обычно делает следующее - выполняет операцию
# utf8::downgrade над данными, работает с результатом как с байтами (на уровне языка Си).
# Соответственно если downgrade не возможен, выдаётся ошибка или warning - Wide character in ...
{
    use utf8 ();
    use Encode (qw/ encode /);

    $many_byte_chr_seq = chr(0x422).chr(0x435).chr(0x441).chr(0x442);

    is( sprintf( "%vd", $many_byte_chr_seq ), "1058.1077.1089.1090",
        "Строка 'Тест' представлена числовыми кодами символов Unicode: 1058.1077.1089.1090"
    );
    ok( utf8::is_utf8($many_byte_chr_seq), "И у нее установлен флаг" );

    eval {
        utf8::downgrade($many_byte_chr_seq);
    };

    ok( $@ =~ /^Wide character in subroutine entry.+/,
        "Но снимать флаг для такой строки нельзя, потому что 'utf8::downgrade()' умеет работать только с байтовым представлением строки"
    );

    $one_byte_chr_seq = encode( 'UTF-8', $many_byte_chr_seq );
    is( sprintf( "%vd", $one_byte_chr_seq ), "208.162.208.181.209.129.209.130",
        "Но если мы работаем с функцией которая умеет работать только с байтами, можно закодировать строку"
    );

    eval {
        utf8::downgrade($one_byte_chr_seq);
    };

    ok( ! $@, "И тогда функция прежде чем работать с такими данными обязательно снимет флаг" );
}


say "--------------- latin test string";

# Первые 127 кодов в ASCII и UTF-8 совпадают
$string = utf8_to_cp1251('Latin test string');
ok( utf8_to_cp1251($string) eq $string, "Первые 127 кодов в ASCII и UTF-8 совпадают" );



say "--------------- flagged utf8 string";

$string = 'test';

# Установим флаг для ASCII строки
{
    use utf8;
    use Encode (qw/ encode decode /);

    $string_u = decode( "UTF-8", encode( "UTF-8", $string ) );
}
ok( utf8::is_utf8($string_u),
    "Установим флаг через encode decode для строки 'test'"
);

# Установим флаг для ASCII строки через split
# split добавит флаг, т.к. на входе есть символы в utf8 - "тест"
{
    use utf8;
    ( $string_u, undef ) = split / /, "$string тест";
}
ok( utf8::is_utf8($string_u),
    "Флаг может быть установлен в результате работы встроенных функций работы со строками"
);

# Установим флаг для ASCII строки через upgrade
{
    use utf8;
    use Encode (qw/ encode decode /);

    $string_u = $string;

    ok( ! utf8::is_utf8($string_u), encode( "UTF-8", "Строка 'test' без флага" ) );

    $num_octets = utf8::upgrade($string_u);
}
is( $num_octets, 4, "Num bytes" );
ok( utf8::is_utf8($string_u), "Используем функцию установки флага" );

{
    my $bytes;

    # Установим флаг для ASCII строки с помощью конкатенации с flagged данными
    {
        use utf8;

        $string_u = $string . ' тест';
    }
    ok( utf8::is_utf8($string_u),
        "Флаг может быть установлен в результате конкатенации строк: 'test' + ' тест'"
    );

    # Последоавательность байт без флага соответствующая unicode строке
    {
        use utf8 ();

        $bytes = $string. ' тест';
        my $got = join ".", map { ord } split //, $bytes;

        is( $got,
            "116.101.115.116.32.209.130.208.181.209.129.209.130",
            "Строка в бинарном представлении без флага"
        );
    }

    # Если вывести эти две строки в utf8 консоль, строка будет одинаковая
    # но внутри perl они не эеквивалентны
    ok( $bytes ne $string_u, "Binary data not eq string data" );
}

# Одинковые строки с флагом и без эквивалентны внутри perl
# если коды символов <= 127
{
    my $string_u1 = $string. 'тест';
    my $string_u2 = $string. 'тест';

    $num_octets = utf8::upgrade($string_u1);

    ok( utf8::is_utf8($string_u1),
        "Строка 1 = 'test тест' в байтовом представлении с установленным флагом"
    );
    ok( ! utf8::is_utf8($string_u2),
        "Строка 2 = 'test тест' в байтовом представлении без флага"
    );
    ok( $string_u1 eq $string_u2, "Но при этом они эквивалентны" );
}


say "--------------- utf8 string from yaml";

# Чтение латинских и кириллических символов из YAML
{
    use YAML::Syck;
    use utf8 ();

    my $strings = YAML::Syck::LoadFile( lib::abs::path 'data.yaml' );

    ok( ! utf8::is_utf8( $strings->{latin_text} ),
        "После чтения из YAML получаем not flagged бинарные данные"
    );
    ok( ! utf8::is_utf8( $strings->{cyrillic_text} ),
        "После чтения из YAML получаем not flagged бинарные данные"
    );

    $num_octets = utf8::upgrade( $strings->{cyrillic_text} );

    my $got = join ".", map { ord } split //, $strings->{cyrillic_text};
    my $expected = '208.162.208.181.209.129.209.130.208.190.208.178.209.139.208.185.32.209.130.208.181.208.186.209.129.209.130';

    ok( utf8::is_utf8( $strings->{cyrillic_text} ), "Установим флаг для кирилического текста из YAML" );
    is( $got, $expected, "После добавления флага, данные так и остаются бинарными но с флагом" );
}


say "--------------- memory using";

# Бинарные данные с флагом utf8 занимают больше памяти
{
    use utf8  ();
    use bytes ();

    # байты, не символы
    my $bin = "\xf1\xf2\xf3";

    is( bytes::length($bin), 3, "Возьмем бинарные данные размером 3 байта" );

    # Установим флаг
    utf8::upgrade($bin);

    is( bytes::length($bin), 6, "Установим для них флаг utf8 и объем данных вырастет до 6 байт" );

    # Возьмем данные длиной 36 байт
    $bin = "\xf1\xf2\xf3\xf1\xf2\xf3\xf1\xf2\xf3\xf1\xf2\xf3\xf1\xf2\xf3\xf1\xf2\xf3\xf1\xf2\xf3\xf1\xf2\xf3\xf1\xf2\xf3\xf1\xf2\xf3\xf1\xf2\xf3\xf1\xf2\xf3";

    is( bytes::length($bin), 36, "Возьмем бинарные данные размером 36 байт" );

    # Установим флаг
    utf8::upgrade($bin);

    is( bytes::length($bin), 72, "Установим для них флаг utf8 и объем данных вырастет до 72 байт" );

    # Снимем флаг
    utf8::downgrade($bin);

    is( bytes::length($bin), 36, "Снимем флаг и объем станет снова равен 36 байт" );
}


say "--------------- in memory";

# Посмотрим как выглядят в памяти данные в разных представлениях
if (0) {
    use utf8;
    use Devel::Peek;

    $string = 'XY';
    Dump $string;
    utf8::downgrade $string;
    Dump $string;

    $string = "µ";
    Dump $string;
    utf8::downgrade $string;
    Dump $string;

    # В памяти символы > 255 хранятся как закодированные байты в utf8,
    # а в перл как числа коды символов из таблицы unicode
    $string = "Ā";
    Dump $string;
}

done_testing();
