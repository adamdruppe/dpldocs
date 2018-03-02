dpldocs.info backend. works with [adrdox](https://github.com/adamdruppe/adrdox).

compile command:

```
dmd -debug -m64 dl ~/arsd/{cgi,dom,http2,jsvar} -version=scgi
```

assuming you have my libs in the same place as i do on my box lol

then you can test locally with

```
	./dl GET /some/path --host whatever.dpldocs.info
```

Note that the directories it wants to write to are hardcoded, as are a few
other things. This code is not meant to be distributed or deployed elsewhere,
it is a quick hack to run on my server for my purposes. I'm only putting it
here in case someone wants to add stuff to it.

btw you MUST put the method (GET or POST or whatever) first on the command line,
and it must be all caps, or else it will think you want to spawn up the scgi server.
