// dmd -debug -g -m64 dl ~/arsd/{cgi,dom,http2,jsvar} -version=scgi  && gzip dl && scp dl.gz root@droplet:/root/dpldocs
// curl -d clear http://dplug.dpldocs.info/reset-cache
// FIXME: drop privs if called as root!!!!!!


// document undocumented by default on dub side. figure out the core.sys problem


// FIXME: figure out how to download bitbucket packages

// Copyright Adam D. Ruppe 2018. All Rights Reserved.
import arsd.dom;
import arsd.http2;
import arsd.cgi;
import arsd.jsvar;
import std.string;
import std.file;
import std.process;
import std.zip;

// rel="nofollow" to the manage page?

/*
	FIXME: read versions[0].sourcePaths off the dub api (it is an array) and use it to limit the source scan. also check sourceFiles, if present.

	skip internal functions (tho adrdox can do that too)
	FIXME: better default entry page
*/

string findRootPage(string project, string versionTag) {
	string endit(string s) {
		if(s.endsWith(".gz"))
			s = s[0 .. $-3];
		if(versionTag == "master")
			return s;
		return "/" ~ versionTag ~ "/" ~ s;
	}

	if(project == "arsd-official")
		return endit("arsd.html");

	foreach(file; [
		project ~ ".html",
		project.replace("-", "_") ~ ".html",
		project.replace("-", "") ~ ".html",
		"index.html",
	])
	{
		if(std.file.exists(buildFilePath(project, versionTag, file, false)))
			return endit(file);
	}

	{
		auto dash = project.indexOf("-");
		if(dash != -1) {
			auto t = project[0 .. dash] ~ ".html";
			if(std.file.exists(buildFilePath(project, versionTag, t, false)))
				return endit(t);
		}
	}

	// fallback on the first file we find...
	foreach(string name; dirEntries(buildFilePath(project, versionTag, "", false), "*.html.gz", SpanMode.shallow)) {
		return endit(name[name.lastIndexOf("/") + 1 .. $]);
	}
	foreach(string name; dirEntries(buildFilePath(project, versionTag, "", true), "*.html.gz", SpanMode.shallow)) {
		name = name[name.lastIndexOf("/") + 1 .. $];
		return endit("source/" ~ name);
	}

	throw new Exception("no file");
}

string buildFilePath(string project, string versionTag, string file, bool sourceRequested) {
	return buildMetaFilePath(project, versionTag, (sourceRequested ? "adrdox-generated/source/" : "adrdox-generated/") ~ file ~ (file.length ? ".gz" : ""));
}

string buildSourceFilePath(string project, string versionTag, string file) {
	return buildMetaFilePath(project, versionTag, "source/" ~ file);
}

string buildMetaFilePath(string project, string versionTag, string path) {
	return "/dpldocs/" ~ project ~ "/" ~ versionTag ~ "/" ~ path;
}

string sanitize(string s) {
	foreach(ch; s) {
		if(!(
			(ch >= 'a' && ch <= 'z') ||
			(ch >= 'A' && ch <= 'Z') ||
			(ch >= '0' && ch <= '9') ||
			ch == '.' ||
			ch == '-' ||
			ch == '_'
		))
		{
			throw new Exception("invalid char");
		}
	}

	return s;
}

void app(Cgi cgi) {
	immutable project = cgi.host.replace(".dpldocs.info", "");
	if(project == "www") {
		cgi.setResponseLocation("https://dpldocs.info/" ~ cgi.pathInfo);
		return;
	}
	string versionTag;
	string file;
	bool sourceRequested;
	string query;
try {

	{
		string path = cgi.requestUri;

		auto q = path.indexOf("?");
		if(q != -1) {
			query = path[q .. $];
			path = path[0 .. q];
		}

		if(path[0] == '/')
			path = path[1 .. $];
		if(path == "search/search") {
			cgi.setResponseLocation("/search-docs.html" ~ query);
			return;
		} else if(path == "arsd.docs.adrdoc.help.html") {
			cgi.setResponseLocation("http://dpldocs.info/experimental-docs/arsd.docs.adrdoc.help.html");
			return;
		} else if(path == "d-logo.png") {
			cgi.setResponseLocation("http://dpldocs.info/d-logo.png");
			return;
		}

		auto idx = path.indexOf("/");
		if(idx != -1) {
			versionTag = path[0 .. idx];
			file = path[idx + 1 .. $];
			if(versionTag == "source") {
				versionTag = "master";
				sourceRequested = true;
			} else if(versionTag.length == 0) {
				cgi.setResponseLocation(cgi.requestUri[1 .. $]);
				return;
			} else if(versionTag != "master" && (versionTag.length <= 3 || (versionTag[0] != 'v' && versionTag[0] != '~'))) {
				cgi.setResponseStatus("404 Not Found");
				cgi.write("Invalid tag, did you forget the leading v in the url?");
				return;
			}
		} else {
			versionTag = "master";
			file = path;
		}

		if(file.startsWith("source/")) {
			sourceRequested = true;
			file = file["source/".length .. $];
		}
	}

	project.sanitize();
	versionTag.sanitize();
	file.sanitize();

	if(project.length == 0)
		throw new Exception("No project requested");
	if(versionTag.length == 0)
		throw new Exception("No version requested");
	if(versionTag != "master" && versionTag[0] != 'v') {
		cgi.setResponseLocation("/v" ~ versionTag ~ "/" ~(sourceRequested ? "source/" : "") ~ file ~ query);
		return;
	}

	if(std.file.exists(buildMetaFilePath(project, versionTag, "success"))) {
		if(file.length == 0) {
			// send to a random page if none requested
			auto f = findRootPage(project, versionTag);
			cgi.setResponseLocation(f);
			return;
		}

		if(cgi.requestMethod == Cgi.RequestMethod.POST && file == "reset-cache") {
			import std.file;
			rmdirRecurse(buildMetaFilePath(project, versionTag, ""));
			cgi.setResponseLocation(cgi.getCurrentCompleteUri[0 .. $-11]);
			return;
		}

		// FIXME: set cache headers

		if(file == "script.js") {
			cgi.setResponseExpiresRelative(60 * 15, true);
			cgi.setResponseContentType("text/javascript");
			cgi.write(std.file.read("/dpldocs-build/script.js"), true);
			return;
		}

		if(file == "search-docs.js") {
			cgi.setResponseContentType("text/javascript");
			cgi.write(std.file.read("/dpldocs-build/search-docs.js"), true);
			return;
		}

		if(file == "style.css") {
			cgi.setResponseExpiresRelative(60 * 15, true);
			cgi.setResponseContentType("text/css");
			cgi.write(std.file.read("/dpldocs-build/style.css"), true);
			return;
		}
		if(file == "robots.txt") {
			cgi.setResponseContentType("text/plain");
			cgi.write(std.file.read("/dpldocs-build/robots.txt"), true);
			return;
		}

		if(file == "favicon.ico") {
			cgi.setResponseExpiresRelative(60 * 60 * 24 * 7, true);
			cgi.setResponseContentType("image/png");
			cgi.write(std.file.read("/dpldocs-build/favicon.ico"), true);
			return;
		}

		if(file == "RobotoSlab-Regular.ttf") {
			cgi.setResponseContentType("font/ttf");
			cgi.setCache(true);
			cgi.write(std.file.read("/dpldocs-build/RobotoSlab-Regular.ttf"), true);
			return;
		}
		if(file == "RobotoSlab-Bold.ttf") {
			cgi.setResponseContentType("font/ttf");
			cgi.setCache(true);
			cgi.write(std.file.read("/dpldocs-build/RobotoSlab-Bold.ttf"), true);
			return;
		}

		try_again:
		auto filePath = buildFilePath(project, versionTag, file, sourceRequested);

		if(std.file.exists(filePath)) {
			auto idx = filePath.lastIndexOf(".");
			auto ext = filePath[idx + 1 .. $];
			bool preZipped;
			if(ext == "gz") {
				preZipped = true;
				auto ugh = filePath[0 .. idx];
				idx = ugh.lastIndexOf(".");
				ext = ugh[idx + 1 .. $];
			}
			switch(ext) {
				case "html":
					cgi.setResponseContentType("text/html");
				break;
				case "css":
					cgi.setResponseContentType("text/css");
				break;
				case "js":
					cgi.setResponseContentType("text/javascript");
				break;
				default:
					cgi.setResponseContentType("text/plain");
			}
			if(preZipped && !cgi.acceptsGzip) {
				// need to unzip it for this client...
				import std.zlib;
				cgi.write(uncompress(std.file.read(filePath), 0, 15 + 32 /* determine format from data */), true);
			} else if(preZipped) {
				cgi.header("Content-Encoding: gzip");
				cgi.gzipResponse = false;
				// prezipped - write the file directly, after
				// saying it is zipped
				cgi.setResponseExpiresRelative(60 * 5, true);
				cgi.write(std.file.read(filePath), true);
			} else {
				// write the file directly
				cgi.setResponseExpiresRelative(60 * 5, true);
				cgi.write(std.file.read(filePath), true);
			}
		} else {
			if(file.startsWith("std.") || file.startsWith("core.")) {
				cgi.setResponseLocation("//dpldocs.info/" ~ file.replace(".html", ""));
			} else {
				cgi.setResponseStatus("404 Not Found");
				auto better = findRootPage(project, versionTag);
				if(better.length)
					cgi.write("404. Try <a href=\"" ~ better ~ "\">" ~ better ~ "</a> as a starting point");
				else
					cgi.write("404 and I don't know what to suggest. send this link to adam plz");
			}
		}
	} else if(std.file.exists(buildMetaFilePath(project, versionTag, "working"))) {
		cgi.write("The project docs are being built, please wait...");
		cgi.write("<script>setTimeout(function() { location.reload(); }, 3000);</script>The project docs are being built, please wait...");
	} else if(std.file.exists(buildMetaFilePath(project, versionTag, "failed"))) {
		import std.datetime;
		if(Clock.currTime - std.file.timeLastModified(buildMetaFilePath(project, versionTag, "failed")) > dur!"days"(1)) {
			std.file.remove(buildMetaFilePath(project, versionTag, "failed"));
			goto try_again;
		}
		cgi.setResponseStatus("500 Internal Service Error");
		cgi.write("The project build failed. copy/paste this link to adam (destructionator@gmail.com) so he can fix the bug. Or the repo is here https://github.com/adamdruppe/dpldocs but i don't often push so it might be out of date.");
		cgi.write("<br><pre>");
		cgi.write(htmlEntitiesEncode(readText(buildMetaFilePath(project, versionTag, "failed"))));
		cgi.write("</pre>");
	} else {
		// build the project
		std.file.mkdirRecurse(buildMetaFilePath(project, versionTag, ""));
		std.file.write(buildMetaFilePath(project, versionTag, "working"), "foo");
		scope(success) {
			std.file.remove(buildMetaFilePath(project, versionTag, "working"));
			std.file.write(buildMetaFilePath(project, versionTag, "success"), "");
		}

		auto j = get("http://code.dlang.org/api/packages/" ~ project ~ "/info");
		cgi.write("Downloading package info...<br>");
		cgi.flush();
		auto answer = j.waitForCompletion();
		if(answer.code != 200 || answer.contentText == "null") { // lol dub
			throw new Exception("no such package (received from dub: " ~ to!string(answer.code) ~ "\n\n"~answer.contentText ~ ")");
		}

		auto json = var.fromJson(answer.contentText);

		string url;
		
		switch(json.repository.kind.get!string) {
			case "github":
				url = "https://github.com/" ~ json.repository.owner.get!string ~ "/" ~ json.repository.project.get!string ~ "/archive/"~versionTag~".zip";
			break;
			case "gitlab":
				url = "https://gitlab.com/" ~ json.repository.owner.get!string ~ "/" ~ json.repository.project.get!string ~ "/-/archive/"~versionTag~"/"
					~ json.repository.project.get!string ~ "-"~versionTag~".zip";
			break;
			case "bitbucket":
				// FIXME

/*

(19:58:21) WebFreak: for this one project zip is https://gitlab.com/<username>/<projectname>/-/archive/<tag>/<projectname>-<tag>.zip
(19:59:03) adam_d_ruppe: k. happen to know bitbucket while you're at it?
(20:00:03) WebFreak: if you want a reliable API, it's https://gitlab.com/api/v4/projects/<id>/repository/archive.zip
(20:00:06) WebFreak: for gitlab
(20:00:16) WebFreak: id == <username>/<projectname>, url encoded
(20:00:23) WebFreak: so <username>%2F<projectname>
(20:00:49) WebFreak: https://docs.gitlab.com/ee/api/repositories.html#get-file-archive here are the docs
(20:02:08) WebFreak: bitbucket (didn't check the API) download is https://bitbucket.org/<username>/<project>/get/<commit-sha (any length)>.zip
*/
			default:
				throw new Exception("idk how to get this package type " ~ json.repository.kind.get!string ~ "");
		}

		redirected:
		auto z = get(url);
		cgi.write("Downloading source code for version "~versionTag~" from "~url~"...<br>\n");
		cgi.flush();
		auto zipAnswer = z.waitForCompletion();
		if(zipAnswer.code != 200) {
			if(zipAnswer.code == 302 || zipAnswer.code == 301) {
				url = zipAnswer.headersHash["Location"];
				goto redirected;
			}
			throw new Exception("zip failed " ~ to!string(zipAnswer.code));
		}

		string jsonVersion = versionTag;
		if(versionTag == "master")
			jsonVersion = "~" ~ versionTag;
		else
			jsonVersion = versionTag[1 .. $];

		string date;
		string homepage;
		string dublink = "http://code.dlang.org/packages/" ~ project;
		string gitlink = "https://github.com/" ~ json.repository.owner.get!string ~ "/" ~ json.repository.project.get!string;

		foreach(item; json.versions) {
			if(item["version"] == jsonVersion) {
				date = item["date"].get!string;
				homepage = item["homepage"].get!string;
				if(homepage == "null") // hack lol
					homepage = null;
				break;
			}
		}

		string headerTitle = project ~ " " ~ (versionTag == "master" ? "~master" : versionTag);
		if(date.length)
			headerTitle ~= " (" ~ date ~ ")";

		cgi.write("Unzipping D files...<br>\n");
		cgi.flush();

		auto archive = new ZipArchive(zipAnswer.content);
		foreach(name, am; archive.directory) {
			if(name.endsWith(".d")) { // || name.endsWith(".di"))
			// FIXME: skip internal things
				auto path = buildSourceFilePath(project, versionTag, name);
				if(name.indexOf("../") != -1) throw new Exception("illegal source filename in zip " ~ path);
				if(name.indexOf("/") == 0) throw new Exception("illegal source filename in zip " ~ path);
				std.file.mkdirRecurse(path[0 .. path.lastIndexOf("/")]);
				archive.expand(am);
				std.file.write(path, am.expandedData);
			}
		}

		cgi.write("Generating documentation... this may take a few minutes...<br>\n");
		auto shellCmd = escapeShellCommand(
			"./doc2", "--copy-standard-files=false",
			"--header-title", headerTitle,
			"--header-link", "Home=" ~ homepage,
			"--header-link", "Dub=" ~ dublink,
			"--header-link", "Repo=" ~ gitlink,
			"-o", buildFilePath(project, versionTag, "", false),
			"-uiz", buildSourceFilePath(project, versionTag, "")
		);

		shellCmd ~= " 2>&1"; // redirect stderr here too so we can easily enough see exception data

		cgi.write("<tt>$ " ~ shellCmd.replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;") ~ "</tt><br>");
		cgi.flush();
		std.file.chdir("/dpldocs-build");
		auto pipes = pipeShell(shellCmd, Redirect.stdout);

		string line;
		while((line = pipes.stdout.readln()) !is null) {
			cgi.write(line.replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;") ~ "<br>");
		}

		if(wait(pipes.pid) == 0) {
			string docurl;

			docurl = findRootPage(project, versionTag);

			if(docurl.length) {
				cgi.write("Success! Sending you to <a href=\"" ~ docurl ~ "\">" ~ docurl ~ "</a>");
				cgi.write("<script> location.reload(true); </script>");
			} else {
				cgi.write("The generator completed, but could find no docs.");
			}
		} else {
			throw new Exception("adrdox failed :(");
		}
	}
} catch(Throwable t) {
	if(std.file.exists(buildMetaFilePath(project, versionTag, "working")))
		std.file.remove(buildMetaFilePath(project, versionTag, "working"));
	std.file.write(buildMetaFilePath(project, versionTag, "failed"), t.toString);
	cgi.write("<br><br>Failed (try contacting destructionator@gmail.com or trying again tomorrow):<br>" ~ t.msg.replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;"));
}
}

mixin GenericMain!app;

