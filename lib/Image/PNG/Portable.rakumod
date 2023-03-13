unit class Image::PNG::Portable;

use String::CRC32;
use Compress::Zlib;

#`[[[
https://rt.perl.org/Public/Bug/Display.html?id=123700
subset UInt of Int where * >= 0;
subset PInt of Int where * > 0;
subset UInt8 of Int where 0 <= * <= 255;
subset NEStr of Str where *.chars;
]]]

has Int $.width = die 'Width is required';
has Int $.height = die 'Height is required';
has Bool $.alpha = True;

has $!channels = $!alpha ?? 4 !! 3;
# + 1 allows filter bytes in the raw data, avoiding needless buf manip later
has $!line-bytes = $!width * $!channels + 1;
has $!data-bytes = $!line-bytes * $!height;
has $!data = buf8.new: 0 xx $!data-bytes;

# magic string for PNGs
constant $magic = blob8.new: 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A;

method set (
    Int $x where * < $!width,
    Int $y where * < $!height,
    Int $r, Int $g, Int $b, Int $a = 255
) {
    my $buffer = $!data;
    # + 1 skips aforementioned filter byte
    my $index = $!line-bytes * $y + $!channels * $x + 1;

    $buffer[$index++] = $r;
    $buffer[$index++] = $g;
    $buffer[$index] = $b;
    $buffer[++$index] = $a if $!alpha;

    True;
}

method set-all (Int $r, Int $g, Int $b, Int $a = 255) {
    my $buffer = $!data;
    my $index = 0;
    my $alpha = $!alpha;

    for ^$!height {
        # every line offset by 1 again for filter byte
        $index++;
        for ^$!width {
            $buffer[$index++] = $r;
            $buffer[$index++] = $g;
            $buffer[$index++] = $b;
            $buffer[$index++] = $a if $alpha;
        }
    }

    True;
}

method get (
    Int $x where * < $!width,
    Int $y where * < $!height
) {
    my $buffer = $!data;
    # + 1 skips aforementioned filter byte
    my $index = $!line-bytes * $y + $!channels * $x + 1;

    my @ret = $buffer[$index++], $buffer[$index++], $buffer[$index];
    @ret[3] = $buffer[++$index] if $!alpha;
    @ret;
}

method Blob {
  [~]
  $magic,
  chunk(
    'IHDR', @(
      |bytes($!width, 4),
      |bytes($!height, 4),
      8, ($!alpha ?? 6 !! 2), 0, 0, 0
    )
  ),
  chunk('IDAT', compress $!data),
  chunk('IEND');
}
sub chunk(Str $type, @data = ()) returns blob8 {
  my @type := $type.encode;
  my @td := @data ~~ Blob ??
      @type ~ @data !!
      blob8.new: @type.list, @data.list;
  [~]
  bytes(@data.elems, 4),
  @td,
  bytes(String::CRC32::crc32 @td)
}

method gist {
  use Base64;
  my @image-chunks = encode-base64(self.Blob).rotor(4096, :partial);

  [~] gather for @image-chunks {
    take "\e_G";
    once take 'a=T,f=100,';

    take 'm=1' if ++$ < @image-chunks;
    take ";" ~ .join;

    take "\e\\";
  }
}

method write (Str $file) {
    given $file.IO.open(:w, :bin) {
      .write: self.Blob;
      .close;
    }
}

# converts a number to a Blob of bytes with optional fixed width
sub bytes (Int $n is copy, Int $count = 0) {
    my @return;

    my $exp = 1;
    $exp++ while 256 ** $exp <= $n;

    if $count {
        my $diff = $exp - $count;
        die 'Overflow' if $diff > 0;
        @return.append(0 xx -$diff) if $diff < 0;
    }

    while $exp {
        my $scale = 256 ** --$exp;
        my $value = $n div $scale;
        @return.push: $value;
        $n -= $value * $scale;
    }

    Blob[uint8].new: @return;
}

