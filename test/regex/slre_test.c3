import slre;
import c::stdio;
import c::string;
import std::io;
import c::stdlib;

int total_tests = 0;
int failed_tests = 0;

macro void warn(String fmt, args...)
{
  io::printf("%s,%s: ", $$FILE, $$LINE); io::printfn(fmt, ...args);
}

macro _assert(expr) 
{
  if (! expr) {
    warn("_assert fail");
    stdlib::exit(0);
  }
}

macro String _str(char* s) 
{
  return ((ZString)s).str_view();
}

fn void main() 
{
  SlreCap[10] caps_a;
  SlreCap* caps = &caps_a[0];
  
  /* Metacharacters */
  _assert(slre::reg_match("$", "abcd", 4, null, 0, 0) == 4);
  _assert(slre::reg_match("^", "abcd", 4, null, 0, 0) == 0);
  _assert(slre::reg_match("x|^", "abcd", 4, null, 0, 0) == 0);
  _assert(slre::reg_match("x|$", "abcd", 4, null, 0, 0) == 4);
  _assert(slre::reg_match("x", "abcd", 4, null, 0, 0) == slre::NO_MATCH);
  _assert(slre::reg_match(".", "abcd", 4, null, 0, 0) == 1);
  _assert(slre::reg_match("^.*\\\\.*$", "c:\\Tools", 8, null, 0, slre::IGNORE_CASE)
    == 8);
  _assert(slre::reg_match("\\", "a", 1, null, 0, 0) == slre::INVALID_METACHARACTER);
  _assert(slre::reg_match("\\x", "a", 1, null, 0, 0) == slre::INVALID_METACHARACTER);
  _assert(slre::reg_match("\\x1", "a", 1, null, 0, 0) == slre::INVALID_METACHARACTER);
  _assert(slre::reg_match("\\x20", " ", 1, null, 0, 0) == 1);

  _assert(slre::reg_match("^.+$", "", 0, null, 0, 0) == slre::NO_MATCH);
  _assert(slre::reg_match("^(.+)$", "", 0, null, 0, 0) == slre::NO_MATCH);
  _assert(slre::reg_match("^([\\+-]?)([\\d]+)$", "+", 1, caps, 10, slre::IGNORE_CASE) == slre::NO_MATCH);
  _assert(slre::reg_match("^([\\+-]?)([\\d]+)$", "+27", 3, caps, 10, slre::IGNORE_CASE) == 3);
  _assert(caps[0].len == 1);
  _assert(caps[0].ptr[0] == '+');
  _assert(caps[1].len == 2);
  _assert(string::memcmp(caps[1].ptr, "27", 2) == 0);

  _assert(slre::reg_match("(tel:\\+(\\d+[\\d-]+\\d))", "tel:+1-201-555-0123;a=b", 23, caps, 10, 0) == 19);
  _assert(caps[1].len == 14);
  _assert(string::memcmp(caps[1].ptr, "1-201-555-0123", 14) == 0);

  /* Character sets */
  _assert(slre::reg_match("[abc]", "1c2", 3, null, 0, 0) == 2);
  _assert(slre::reg_match("[abc]", "1C2", 3, null, 0, 0) == slre::NO_MATCH);
  _assert(slre::reg_match("[abc]", "1C2", 3, null, 0, slre::IGNORE_CASE) == 2);
  _assert(slre::reg_match("[.2]", "1C2", 3, null, 0, 0) == 1);
  _assert(slre::reg_match("[\\S]+", "ab cd", 5, null, 0, 0) == 2);
  _assert(slre::reg_match("[\\S]+\\s+[tyc]*", "ab cd", 5, null, 0, 0) == 4);
  _assert(slre::reg_match("[\\d]", "ab cd", 5, null, 0, 0) == slre::NO_MATCH);
  _assert(slre::reg_match("[^\\d]", "ab cd", 5, null, 0, 0) == 1);
  _assert(slre::reg_match("[^\\d]+", "abc123", 6, null, 0, 0) == 3);
  _assert(slre::reg_match("[1-5]+", "123456789", 9, null, 0, 0) == 5);
  _assert(slre::reg_match("[1-5a-c]+", "123abcdef", 9, null, 0, 0) == 6);
  _assert(slre::reg_match("[1-5a-]+", "123abcdef", 9, null, 0, 0) == 4);
  _assert(slre::reg_match("[1-5a-]+", "123a--2oo", 9, null, 0, 0) == 7);
  _assert(slre::reg_match("[htps]+://", "https://", 8, null, 0, 0) == 8);
  _assert(slre::reg_match("[^\\s]+", "abc def", 7, null, 0, 0) == 3);
  _assert(slre::reg_match("[^fc]+", "abc def", 7, null, 0, 0) == 2);
  _assert(slre::reg_match("[^d\\sf]+", "abc def", 7, null, 0, 0) == 3);

  /* Flags - case sensitivity */
  _assert(slre::reg_match("FO", "foo", 3, null, 0, 0) == slre::NO_MATCH);
  _assert(slre::reg_match("FO", "foo", 3, null, 0, slre::IGNORE_CASE) == 2);
  
  _assert(slre::reg_match("(?m)FO", "foo", 3, null, 0, 0) ==
    slre::UNEXPECTED_QUANTIFIER);
  _assert(slre::reg_match("(?m)x", "foo", 3, null, 0, 0) ==
    slre::UNEXPECTED_QUANTIFIER);

  _assert(slre::reg_match("fo", "foo", 3, null, 0, 0) == 2);
  _assert(slre::reg_match(".+", "foo", 3, null, 0, 0) == 3);
  _assert(slre::reg_match(".+k", "fooklmn", 7, null, 0, 0) == 4);
  _assert(slre::reg_match(".+k.", "fooklmn", 7, null, 0, 0) == 5);
  _assert(slre::reg_match("p+", "fooklmn", 7, null, 0, 0) == slre::NO_MATCH);
  _assert(slre::reg_match("ok", "fooklmn", 7, null, 0, 0) == 4);
  _assert(slre::reg_match("lmno", "fooklmn", 7, null, 0, 0) == slre::NO_MATCH);
  _assert(slre::reg_match("mn.", "fooklmn", 7, null, 0, 0) == slre::NO_MATCH);
  _assert(slre::reg_match("o", "fooklmn", 7, null, 0, 0) == 2);
  _assert(slre::reg_match("(^o)", "fooklmn", 7, null, 0, 0) == slre::NO_MATCH);
  _assert(slre::reg_match("^", "fooklmn", 7, null, 0, 0) == 0);
  _assert(slre::reg_match("n$", "fooklmn", 7, null, 0, 0) == 7);
  _assert(slre::reg_match("n$k", "fooklmn", 7, null, 0, 0) == slre::NO_MATCH);
  _assert(slre::reg_match("l$", "fooklmn", 7, null, 0, 0) == slre::NO_MATCH);
  _assert(slre::reg_match(".$", "fooklmn", 7, null, 0, 0) == 7);
  _assert(slre::reg_match("a?", "fooklmn", 7, null, 0, 0) == 0);
  _assert(slre::reg_match("^a*CONTROL", "CONTROL", 7, null, 0, 0) == 7);
  _assert(slre::reg_match("^[a]*CONTROL", "CONTROL", 7, null, 0, 0) == 7);
  _assert(slre::reg_match("^(a*)CONTROL", "CONTROL", 7, null, 0, 0) == 7);
  _assert(slre::reg_match("^(a*)?CONTROL", "CONTROL", 7, null, 0, 0) == 7);

  _assert(slre::reg_match("\\_", "abc", 3, null, 0, 0) == slre::INVALID_METACHARACTER);
  _assert(slre::reg_match("+", "fooklmn", 7, null, 0, 0) == slre::UNEXPECTED_QUANTIFIER);
  _assert(slre::reg_match("()+", "fooklmn", 7, null, 0, 0) == slre::NO_MATCH);
  _assert(slre::reg_match("\\x", "12", 2, null, 0, 0) == slre::INVALID_METACHARACTER);
  _assert(slre::reg_match("\\xhi", "12", 2, null, 0, 0) == slre::INVALID_METACHARACTER);
  _assert(slre::reg_match("\\x20", "_ J", 3, null, 0, 0) == 2);
  _assert(slre::reg_match("\\x4A", "_ J", 3, null, 0, 0) == 3);
  _assert(slre::reg_match("\\d+", "abc123def", 9, null, 0, 0) == 6);

  /* Balancing brackets */
  _assert(slre::reg_match("(x))", "fooklmn", 7, null, 0, 0) == slre::UNBALANCED_BRACKETS);
 
  _assert(slre::reg_match("(", "fooklmn", 7, null, 0, 0) == slre::UNBALANCED_BRACKETS);

  _assert(slre::reg_match("klz?mn", "fooklmn", 7, null, 0, 0) == 7);
  _assert(slre::reg_match("fa?b", "fooklmn", 7, null, 0, 0) == slre::NO_MATCH);

  /* Brackets & capturing */
  _assert(slre::reg_match("^(te)", "tenacity subdues all", 20, caps, 10, 0) == 2);
  _assert(slre::reg_match("(bc)", "abcdef", 6, caps, 10, 0) == 3);
  _assert(slre::reg_match(".(d.)", "abcdef", 6, caps, 10, 0) == 5);
  _assert(slre::reg_match(".(d.)\\)?", "abcdef", 6, caps, 10, 0) == 5);
  _assert(caps[0].len == 2);
  _assert(string::memcmp(caps[0].ptr, "de", 2) == 0);
  _assert(slre::reg_match("(.+)", "123", 3, caps, 10, 0) == 3);
  _assert(slre::reg_match("(2.+)", "123", 3, caps, 10, 0) == 3);
  _assert(caps[0].len == 2);
  _assert(string::memcmp(caps[0].ptr, "23", 2) == 0);
  _assert(slre::reg_match("(.+2)", "123", 3, caps, 10, 0) == 2);
  _assert(caps[0].len == 2);
  _assert(string::memcmp(caps[0].ptr, "12", 2) == 0);
  _assert(slre::reg_match("(.*(2.))", "123", 3, caps, 10, 0) == 3);
  _assert(slre::reg_match("(.)(.)", "123", 3, caps, 10, 0) == 2);
  _assert(slre::reg_match("(\\d+)\\s+(\\S+)", "12 hi", 5, caps, 10, 0) == 5);
  _assert(slre::reg_match("ab(cd)+ef", "abcdcdef", 8, null, 0, 0) == 8);
  _assert(slre::reg_match("ab(cd)*ef", "abcdcdef", 8, null, 0, 0) == 8);
  _assert(slre::reg_match("ab(cd)+?ef", "abcdcdef", 8, null, 0, 0) == 8);
  _assert(slre::reg_match("ab(cd)+?.", "abcdcdef", 8, null, 0, 0) == 5);
  _assert(slre::reg_match("ab(cd)?", "abcdcdef", 8, null, 0, 0) == 4);
  _assert(slre::reg_match("a(b)(cd)", "abcdcdef", 8, caps, 1, 0) ==
      slre::CAPS_ARRAY_TOO_SMALL);
  _assert(slre::reg_match("(.+/\\d+\\.\\d+)\\.jpg$", "/foo/bar/12.34.jpg", 18, caps, 1, 0) == 18);
  _assert(slre::reg_match("(ab|cd).*\\.(xx|yy)", "ab.yy", 5, null, 0, 0) == 5);
  _assert(slre::reg_match(".*a", "abcdef", 6, null, 0, 0) == 1);
  _assert(slre::reg_match("(.+)c", "abcdef", 6, null, 0, 0) == 3);
  _assert(slre::reg_match("\\n", "abc\ndef", 7, null, 0, 0) == 4);
  _assert(slre::reg_match("b.\\s*\\n", "aa\r\nbb\r\ncc\r\n\r\n", 14, caps, 10, 0) == 8);

  /* Greedy vs non-greedy */
  _assert(slre::reg_match(".+c", "abcabc", 6, null, 0, 0) == 6);
  _assert(slre::reg_match(".+?c", "abcabc", 6, null, 0, 0) == 3);
  _assert(slre::reg_match(".*?c", "abcabc", 6, null, 0, 0) == 3);
  _assert(slre::reg_match(".*c", "abcabc", 6, null, 0, 0) == 6);
  _assert(slre::reg_match("bc.d?k?b+", "abcabc", 6, null, 0, 0) == 5);

  /* Branching */
  _assert(slre::reg_match("|", "abc", 3, null, 0, 0) == 0);
  _assert(slre::reg_match("|.", "abc", 3, null, 0, 0) == 1);
  _assert(slre::reg_match("x|y|b", "abc", 3, null, 0, 0) == 2);
  _assert(slre::reg_match("k(xx|yy)|ca", "abcabc", 6, null, 0, 0) == 4);
  _assert(slre::reg_match("k(xx|yy)|ca|bc", "abcabc", 6, null, 0, 0) == 3);
  _assert(slre::reg_match("(|.c)", "abc", 3, caps, 10, 0) == 3);
  _assert(caps[0].len == 2);
  _assert(string::memcmp(caps[0].ptr, "bc", 2) == 0);
  _assert(slre::reg_match("a|b|c", "a", 1, null, 0, 0) == 1);
  _assert(slre::reg_match("a|b|c", "b", 1, null, 0, 0) == 1);
  _assert(slre::reg_match("a|b|c", "c", 1, null, 0, 0) == 1);
  _assert(slre::reg_match("a|b|c", "d", 1, null, 0, 0) == slre::NO_MATCH);

  /* Optional match at the end of the string */
  _assert(slre::reg_match("^.*c.?$", "abc", 3, null, 0, 0) == 3);
  _assert(slre::reg_match("^.*C.?$", "abc", 3, null, 0, slre::IGNORE_CASE) == 3);
  _assert(slre::reg_match("bk?", "ab", 2, null, 0, 0) == 2);
  _assert(slre::reg_match("b(k?)", "ab", 2, null, 0, 0) == 2);
  _assert(slre::reg_match("b[k-z]*", "ab", 2, null, 0, 0) == 2);
  _assert(slre::reg_match("ab(k|z|y)*", "ab", 2, null, 0, 0) == 2);
  _assert(slre::reg_match("[b-z].*", "ab", 2, null, 0, 0) == 2);
  _assert(slre::reg_match("(b|z|u).*", "ab", 2, null, 0, 0) == 2);
  _assert(slre::reg_match("ab(k|z|y)?", "ab", 2, null, 0, 0) == 2);
  _assert(slre::reg_match(".*", "ab", 2, null, 0, 0) == 2);
  _assert(slre::reg_match(".*$", "ab", 2, null, 0, 0) == 2);
  _assert(slre::reg_match("a+$", "aa", 2, null, 0, 0) == 2);
  _assert(slre::reg_match("a*$", "aa", 2, null, 0, 0) == 2);
  _assert(slre::reg_match( "a+$" ,"Xaa", 3, null, 0, 0) == 3);
  _assert(slre::reg_match( "a*$" ,"Xaa", 3, null, 0, 0) == 3);

  /* Ignore case flag */
  _assert(slre::reg_match("[a-h]+", "abcdefghxxx", 11, null, 0, 0) == 8);
  _assert(slre::reg_match("[A-H]+", "ABCDEFGHyyy", 11, null, 0, 0) == 8);
  _assert(slre::reg_match("[a-h]+", "ABCDEFGHyyy", 11, null, 0, 0) == slre::NO_MATCH);
  _assert(slre::reg_match("[A-H]+", "abcdefghyyy", 11, null, 0, 0) == slre::NO_MATCH);
  _assert(slre::reg_match("[a-h]+", "ABCDEFGHyyy", 11, null, 0, slre::IGNORE_CASE) == 8);
  _assert(slre::reg_match("[A-H]+", "abcdefghyyy", 11, null, 0, slre::IGNORE_CASE) == 8);

  {
    /* Example: HTTP request */
    char *request = " GET /index.html HTTP/1.0\r\n\r\n";
    // SlreCap[4] caps;

    if (slre::reg_match("^\\s*(\\S+)\\s+(\\S+)\\s+HTTP/(\\d)\\.(\\d)", request, (int)string::strlen(request), caps, 4, 0) > 0) {
      io::printf("Method: [%.*s], URI: [%.*s]\n", caps[0].len, _str(caps[0].ptr), caps[1].len, _str(caps[1].ptr));
    } else {
      io::printf("Error parsing [%s]\n", _str(request));
    }

    _assert(caps[1].len == 11);
    _assert(string::memcmp(caps[1].ptr, "/index.html", caps[1].len) == 0);
  }

  {
    /* Example: string replacement */
    char *s = slre::reg_replace("({{.+?}})", "Good morning, {{foo}}. How are you, {{bar}}?", "Bob");
    io::printf("%s\n", _str(s));
    _assert(string::strcmp(s, "Good morning, Bob. How are you, Bob?") == 0);
    stdlib::free(s);
  }

  {
    /* Example: find all URLs in a string */
    char *str =
      "<img src=\"HTTPS://FOO.COM/x?b#c=tab1\"/>   <a href=\"http://cesanta.com\">some link</a>";

    char *regex = "((https?://)[^\\s/'\"<>]+/?[^\\s'\"<>]*)";
    // SlreCap[2] caps;
    int i;
    int j = 0;
    int str_len = (int) string::strlen(str);

    while (j < str_len &&
           (i = slre::reg_match(regex, str + j, str_len - j, caps, 2, slre::IGNORE_CASE)) > 0) {
      io::printf("Found URL: [%.*s]\n", caps[0].len, _str(caps[0].ptr));
      j += i;
    }
  }

  {
    /* Example more complex regular expression */
    char * str = "aa 1234 xy\nxyz";
    char * regex = "aa ([0-9]*) *([x-z]*)\\s+xy([yz])";
    // SlreCap[3] caps;
    _assert(slre::reg_match(regex, str, (int)string::strlen(str), caps, 3, 0) > 0);
    _assert(caps[0].len == 4);
    _assert(caps[1].len == 2);
    _assert(caps[2].len == 1);
    _assert(caps[2].ptr[0] == 'z');
  }
}
