// opak: PNG dosyalarını alfa kanalı olmadan yeniden yazar (App Store iOS simgesi alfa kabul etmez).
// Kullanım: go run ./tool/opak dosya.png...
package main

import (
	"image"
	"image/color"
	"image/draw"
	"image/png"
	"os"
)

func main() {
	for _, f := range os.Args[1:] {
		in, err := os.Open(f)
		if err != nil {
			panic(err)
		}
		src, err := png.Decode(in)
		in.Close()
		if err != nil {
			panic(err)
		}
		b := src.Bounds()
		dst := image.NewRGBA(b)
		draw.Draw(dst, b, &image.Uniform{color.RGBA{0x54, 0x43, 0xD2, 0xff}}, image.Point{}, draw.Src)
		draw.Draw(dst, b, src, b.Min, draw.Over)
		out, err := os.Create(f)
		if err != nil {
			panic(err)
		}
		if err := png.Encode(out, dst); err != nil { // opaque image → PNG truecolor without alpha
			panic(err)
		}
		out.Close()
	}
}
