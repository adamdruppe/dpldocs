//  dmd -debug  -m64 dl ~/arsd/{cgi,dom,http2,jsvar} -version=scgi  && gzip dl && scp dl.gz root@droplet:/root/dpldocs
// FIXME: drop privs if called as root!!!!!!
import arsd.dom;
import arsd.http2;
import arsd.cgi;
import arsd.jsvar;
import std.string;
import std.file;
import std.process;
import std.zip;

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

	foreach(file; [
		"index.html",
		project ~ ".html",
		project.replace("-", "_") ~ ".html",
		project.replace("-", "") ~ ".html"
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
		auto idx = path.indexOf("/");
		if(idx != -1) {
			versionTag = path[0 .. idx];
			file = path[idx + 1 .. $];
			if(versionTag == "source") {
				versionTag = "master";
				sourceRequested = true;
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

		// FIXME: set cache headers

		if(file == "script.js") {
			cgi.setResponseContentType("text/javascript");
			cgi.write(std.file.read("/dpldocs-build/script.js"), true);
			return;

		}

		if(file == "style.css") {
			cgi.setResponseContentType("text/css");
			cgi.write(std.file.read("/dpldocs-build/style.css"), true);
			return;
		}

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
			if(preZipped) {
				cgi.header("Content-Encoding: gzip");
				cgi.gzipResponse = false;
			}
			cgi.write(std.file.read(filePath), true);
		} else {
			cgi.setResponseStatus("404 Not Found");
			auto better = findRootPage(project, versionTag);
			if(better.length)
				cgi.write("404. Try <a href=\"" ~ better ~ "\">" ~ better ~ "</a> as a starting point");
			else
				cgi.write("404 and I don't know what to suggest. send this link to adam plz");
		}
	} else if(std.file.exists(buildMetaFilePath(project, versionTag, "working"))) {
		cgi.write("The project docs are being built, please wait...");
	} else if(std.file.exists(buildMetaFilePath(project, versionTag, "failed"))) {
		cgi.write("The project build failed. copy/paste this link to adam so he can fix the bug.");
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
		if(answer.code != 200) {
			throw new Exception("no such package");
		}

		auto json = var.fromJson(answer.contentText);
		if(json.repository.kind != "github") {
			throw new Exception("idk how to get this package");
		}

		auto url = "https://github.com/" ~ json.repository.owner.get!string ~ "/" ~ json.repository.project.get!string ~ "/archive/"~versionTag~".zip";

		redirected:
		auto z = get(url);
		cgi.write("Downloading source code for version "~versionTag~" from "~url~"...<br>\n");
		cgi.flush();
		auto zipAnswer = z.waitForCompletion();
		if(zipAnswer.code != 200) {
			if(zipAnswer.code == 302) {
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
				auto path = buildSourceFilePath(project, versionTag, name);
				if(path.indexOf("../") != -1) throw new Exception("illegal source filename in zip");
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
			cgi.write("adrdox failed :(");
			throw new Exception("suck");
		}
	}
} catch(Throwable t) {
	if(std.file.exists(buildMetaFilePath(project, versionTag, "working")))
		std.file.remove(buildMetaFilePath(project, versionTag, "working"));
	std.file.write(buildMetaFilePath(project, versionTag, "failed"), t.toString);
	cgi.write("<br><br>Failed:<br>" ~ t.msg.replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;"));
}
}

mixin GenericMain!app;
