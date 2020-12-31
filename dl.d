// dmdi -debug -g -m64 dl -version=scgi  && gzip dl && scp dl.gz root@droplet:/root/dpldocs
// curl -d clear http://dplug.dpldocs.info/reset-cache
// FIXME: drop privs if called as root!!!!!!


// document undocumented by default on dub side. figure out the core.sys problem


// Copyright Adam D. Ruppe 2018. All Rights Reserved.
import arsd.dom;
import arsd.http2;
import arsd.cgi;
import arsd.jsvar;
import std.string;
import std.file;
import std.process;
import std.zip;

import arsd.postgres;

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
			|| ch == '~' || ch == '(' || ch == ')' // like this(this) and ~master
		))
		{
			throw new UserErrorException("invalid char");
		}
	}

	return s;
}

class UserErrorException : Exception {
	this(string s, string file = __FILE__, size_t line = __LINE__) {
		super(s, file, line);
	}
}
class DubException : Exception {
	this(string s, string file = __FILE__, size_t line = __LINE__) {
		super(s, file, line);
	}
}
class RepoException : Exception {
	this(string s, string file = __FILE__, size_t line = __LINE__) {
		super(s, file, line);
	}
}

void app(Cgi cgi) {
	immutable project = cgi.host.replace(".dpldocs.info", "");
	import std.algorithm;
	if(project == "www") {
		cgi.setResponseLocation("https://dpldocs.info/" ~ cgi.pathInfo);
		return;
	} else if(project.canFind(".")) {
		cgi.setResponseStatus("404 Not Found");
		cgi.write("Invalid domain", true);
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
		throw new UserErrorException("No project requested");
	if(versionTag.length == 0)
		throw new UserErrorException("No version requested");
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
		if(Clock.currTime - std.file.timeLastModified(buildMetaFilePath(project, versionTag, "failed")) > dur!"hours"(6)) {
			std.file.remove(buildMetaFilePath(project, versionTag, "failed"));
			goto try_again;
		}
		cgi.setResponseStatus("500 Internal Service Error");
		cgi.write("The project build failed. It will try again in about 6 hours or you can copy/paste this link to adam (destructionator@gmail.com) so he can fix the bug and/or reset it early. Or the repo is here https://github.com/adamdruppe/dpldocs but i don't often push so it might be out of date.");
		cgi.write("<br><pre>");
		cgi.write(htmlEntitiesEncode(readText(buildMetaFilePath(project, versionTag, "failed"))));
		cgi.write("</pre>");
	} else {


		auto db = new PostgreSql("dbname=adrdox user=root");

		// build the project
		std.file.mkdirRecurse(buildMetaFilePath(project, versionTag, ""));
		std.file.write(buildMetaFilePath(project, versionTag, "working"), "foo");
		scope(success) {
			std.file.remove(buildMetaFilePath(project, versionTag, "working"));
			std.file.write(buildMetaFilePath(project, versionTag, "success"), "");
		}

		HttpResponse answer;

		if(project == "druntime")
			goto skip_dub;

		try {
			auto j = get("http://code.dlang.org/api/packages/" ~ project ~ "/info");
			cgi.write("Downloading package info...<br>");
			cgi.flush();
			answer = j.waitForCompletion();
			if(answer.code != 200 || answer.contentText == "null") { // lol dub
				throw new DubException("no such package (received from dub: " ~ to!string(answer.code) ~ "\n\n"~answer.contentText ~ ")");
			}
		} catch(DubException e) {
			throw e;
		} catch(Exception e) {
			throw new DubException(e.toString());
		}

		skip_dub:
		var json;

		if(project == "druntime") {
			// druntime not on dub but i want to pretend it is
			auto dlVersion = versionTag;

			json = var.fromJson(`{
				"repository": { "kind":"github", "owner": "dlang", "project":"druntime" },
				"name" : "druntime",
				"versions": {}
			}`);
		} else {
			json = var.fromJson(answer.contentText);
		}

		string url;
		
		switch(json.repository.kind.get!string) {
			case "github":

				auto dlVersion = versionTag;

				if(dlVersion == "master") {
					auto client = new HttpApiClient!()("https://api.github.com/", null);
					client.httpClient.userAgent = "adamdruppe-dpldocs";
					auto info = client.rest.repos[json.repository.owner.get!string][json.repository.project.get!string].GET().result;
					dlVersion = info.default_branch.get!string;
				}

				url = "https://github.com/" ~ json.repository.owner.get!string ~ "/" ~ json.repository.project.get!string ~ "/archive/"~dlVersion~".zip";
			break;
			// thanks to WebFreak on IRC for helping with these
			case "gitlab":
				url = "https://gitlab.com/" ~ json.repository.owner.get!string ~ "/" ~ json.repository.project.get!string ~ "/-/archive/"~versionTag~"/"
					~ json.repository.project.get!string ~ "-"~versionTag~".zip";
			break;
			case "bitbucket":
				url = "https://bitbucket.org/"~ json.repository.owner.get!string ~ "/"~ json.repository.project.get!string ~"/get/" ~versionTag~ ".zip";
			break;
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
				if("Location" in zipAnswer.headersHash)
					url = zipAnswer.headersHash["Location"];
				else
					url = zipAnswer.headersHash["location"];
				goto redirected;
			}
			throw new RepoException("zip failed " ~ to!string(zipAnswer.code));
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

		if(project == "druntime") {
			homepage = "http://dlang.org/";
			date = Clock.currTime.toISOExtString;
		}

		foreach(item; json.versions) {
			if(item["version"] == jsonVersion) {
				date = item["date"].get!string;
				homepage = item["homepage"].get!string;
				if(homepage == "null") // hack lol
					homepage = null;
				break;
			}
		}

		if(date.length == 0)
			date = Clock.currTime.toISOExtString;

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

		auto dubName = json.name.get!string;

		string dpid;
		foreach(row; db.query("SELECT id FROM dub_package WHERE name = ?", dubName))
			dpid = row[0];
		if(dpid.length == 0) {
			foreach(row; db.query("INSERT INTO dub_package (name, url_name, description, adrdox_cmdline_options) VALUES (?, ?, ?, '') RETURNING id",
			dubName, dubName, json.versions[0].description.get!string))
				dpid = row[0];
		}

		string pvid;
		foreach(row; db.query("SELECT id FROM package_version WHERE dub_package_id = ? AND version_tag = ?", dpid, versionTag))
			pvid = row[0];

		if(pvid.length == 0) {
			foreach(row; db.query("INSERT INTO package_version (dub_package_id, version_tag, release_date, is_latest) VALUES (?, ?, ?, ?) RETURNING id",
				dpid, versionTag, date, versionTag == "master"))
			{
				pvid = row[0];
			}
		}

		// FIXME: if it is master we could update the release date

		cgi.write("Generating documentation... this may take a few minutes...<br>\n");
		auto shellCmd = escapeShellCommand(
			"./doc2", "--copy-standard-files=false",
			"--header-title", headerTitle,
			"--header-link", "Home=" ~ homepage,
			"--header-link", "Dub=" ~ dublink,
			"--header-link", "Repo=" ~ gitlink,
			"--package-path", "core.*=//dpldocs.info/experimental-docs/",
			"--package-path", "std.*=//phobos.dpldocs.info/",
			"--package-path", "arsd.*=//arsd-official.dpldocs.info/",

			"--postgresConnectionString", "dbname=adrdox user=root",
			"--postgresVersionId", to!string(pvid),

			"--document-undocumented",
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
} catch(UserErrorException t) {
	if(std.file.exists(buildMetaFilePath(project, versionTag, "working")))
		std.file.remove(buildMetaFilePath(project, versionTag, "working"));

	cgi.write("<br><br>You need to fix your url:<br>" ~ t.msg.replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;"));
} catch(Throwable t) {
	if(std.file.exists(buildMetaFilePath(project, versionTag, "working")))
		std.file.remove(buildMetaFilePath(project, versionTag, "working"));
	std.file.write(buildMetaFilePath(project, versionTag, "failed"), t.toString);
	cgi.write("<br><br>Failed (try contacting destructionator@gmail.com or trying again tomorrow; the retry timeout is about 6 hours):<br>" ~ t.msg.replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;"));
}
}

mixin GenericMain!app;

