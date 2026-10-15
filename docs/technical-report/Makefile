PDF = main.pdf

all: $(PDF)

main.pdf: main.tex $(wildcard chapters/*.tex)
	tectonic -X compile main.tex

cp: main.pdf
	cp main.pdf LexiLingo_BaoCaoKyThuat.pdf

clean:
	rm -f main.pdf main.aux main.log main.toc main.out

.PHONY: all clean cp
