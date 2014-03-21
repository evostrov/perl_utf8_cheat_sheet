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

    Схема преобразования байтов в коды utf8:
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

{
    # При подключении модуля utf8 он уже распознается как символ и perl работает со строкой
    # состоящей из двух символов: [ 鸡 \n ]
    use utf8;

    $many_byte_chr_seq = "鸡\n";
}

is( ( join ".", map { ord } split //, $many_byte_chr_seq ), "40481.10",
    "С включеной прагмой 'use utf8;' перл понимает unicode символы как набор числовых кодов Unicode"
);


say "--------------- use byte;";

# Сохраним строку из двух символов, perl будет работать с такими данными как со строкой
# chr(127) - последний возможный символ в одно байтовой кодировке.
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

# Если перлу передать на печать cp1251 код, и указать что консоль работает в utf8
# он будет превращать байты кода cp1251 в коды utf8
# Например кирилическая прописная "Т" в cp1251 это равно байту 210
# а при вывод это байт будет воспринят как unicode, что соответствует байту 0xD2
# т.е. символу "Ò"
{
    $string = utf8_to_cp1251('Тест');
    binmode( STDOUT, ':utf8' );
    say $string; # Напечатает в utf8 консоли "Òåñò"
    binmode( STDOUT );
}


say "--------------- functions tests";

# Не все функции умеют работать с внутренним представлением строк в виде кодов символов
{
    use utf8 ();

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



















done_testing();
