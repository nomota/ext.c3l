
import ext::regex;

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
  warn("%d tests passed.", ++total_tests);
}

macro String _str(char* s) 
{
  return ((ZString)s).str_view();
}

const int IGNORE_CASE = 1;
const int NO_MATCH = -1;

struct Match {
  char* ptr;
  int len;
}

fn int? __reg_match(String expr, String str, int len, Match *m, int mlen, int flag) 
{
  RegEx* reg = regex::new_compile(mem, expr, flag == IGNORE_CASE)!;
  defer reg.free();
 
  warn("expr:%s, str:%s match..", expr, str); 

  int start;
  int? result = reg.match(str, &start, &len);
  if (catch err = result) {
    warn("expr:%s, str:%s, err:%s", expr, str, err); 
    return err~;
  } else if (result < 0) {
    warn("expr:%s, str:%s, NO_MATCH", expr, str); 
    return NO_MATCH;
  }
  
  if (m != null) {
    for (int i = 0; i < mlen; i++) {
      RegMatch? g = reg.group(i);
      if (catch err = g) break;
      warn("i:%d, pos:%d, len:%d", i, g.pos, g.len);
      m[i].ptr = &reg.str[g.pos];
      m[i].len = g.len;
    }
  }
  warn("expr:%s, str:%s, start: %d, len: %d", expr, str, start, len);
  return result;
}

faultdef NO_ERR;

fn fault __reg_match_e(String expr, String str, int len, Match *m, int mlen, int flag) 
{
  int? x = __reg_match(expr, str, len, m, mlen, flag);
  if (catch err = x) {
    warn("expr:%s, str:%s, err:%s", expr, str, err); 
    return err;
  }
  warn("expr:%s, str:%s, err:%s", expr,  str, NO_ERR); 

  return NO_ERR;
}

fn String? __reg_replace(String expr, String str, String sub) 
{
  String s = regex::reg_replace(mem, expr, str, sub)!;
  return s;
}

fn void main() 
{
  Match[10] match;
  Match* caps = &match[0];
  warn("-");
  _assert(__reg_match("(a+)", "baabcd", 4, null, 0, 0)!! == 3);

  // Metacharacters 
  _assert(__reg_match("$", "abcd", 4, null, 0, 0)!! == 4);
  _assert(__reg_match("^", "abcd", 4, null, 0, 0)!! == 0);
 
  _assert(__reg_match("x|^", "abcd", 4, null, 0, 0)!! == 0);
  _assert(__reg_match("x|$", "abcd", 4, null, 0, 0)!! == 4);
  _assert(__reg_match("x", "abcd", 4, null, 0, 0)!! == NO_MATCH);
  warn("-");
  
  _assert(__reg_match(".", "abcd", 4, null, 0, 0)!! == 1);
  _assert(__reg_match("^.*\\\\.*$", "c:\\Tools", 8, null, 0, IGNORE_CASE)!!
    == 8);
  warn("-");
  
  _assert(__reg_match_e("\\", "a", 1, null, 0, 0) == regex::INVALID_METACHARACTER);
 
  _assert(__reg_match_e("\\x", "a", 1, null, 0, 0) == regex::INVALID_METACHARACTER);
  _assert(__reg_match_e("\\x1", "a", 1, null, 0, 0) == regex::INVALID_METACHARACTER);
  _assert(__reg_match("\\x20", " ", 1, null, 0, 0)!! == 1);

  _assert(__reg_match_e("^.+$", "", 0, null, 0, 0) == regex::EMPTY_STR);
  _assert(__reg_match_e("^(.+)$", "", 0, null, 0, 0) == regex::EMPTY_STR);
  _assert(__reg_match("^([\\+-]?)([\\d]+)$", "+", 1, caps, 10, IGNORE_CASE)!! == NO_MATCH);
  _assert(__reg_match(`^([\+-]?)([\d]+)$`, "+27", 3, caps, 10, IGNORE_CASE)!! == 3);
  _assert(caps[1].len == 1);
  _assert(caps[1].ptr[0] == '+');
  _assert(caps[2].len == 2);
  _assert(string::memcmp(caps[2].ptr, "27", 2) == 0);

  _assert(__reg_match("tel:\\+(\\d+[\\d-]+\\d)", "tel:+1-201-555-0123;a=b", 23, caps, 10, 0)!! == 19);
  _assert(caps[1].len == 14);
  _assert(string::memcmp(caps[1].ptr, "1-201-555-0123", 14) == 0);

  // Character sets 
  _assert(__reg_match("[abc]", "1c2", 3, null, 0, 0)!! == 2);
  _assert(__reg_match("[abc]", "1C2", 3, null, 0, 0)!! == NO_MATCH);
  _assert(__reg_match("[abc]", "1C2", 3, null, 0, IGNORE_CASE)!! == 2);
  _assert(__reg_match("[.2]", "1C2", 3, null, 0, 0)!! == 1);
 
  _assert(__reg_match("[\\S]+", "ab cd", 5, null, 0, 0)!! == 2);
  _assert(__reg_match("[\\S]+\\s+[tyc]*", "ab cd", 5, null, 0, 0)!! == 4);
  _assert(__reg_match("[\\d]", "ab cd", 5, null, 0, 0)!! == NO_MATCH);
  _assert(__reg_match("[^\\d]", "ab cd", 5, null, 0, 0)!! == 1);
  _assert(__reg_match("[^\\d]+", "abc123", 6, null, 0, 0)!! == 3);
  _assert(__reg_match("[1-5]+", "123456789", 9, null, 0, 0)!! == 5);
  _assert(__reg_match("[1-5a-c]+", "123abcdef", 9, null, 0, 0)!! == 6);
  _assert(__reg_match("[1-5a-]+", "123abcdef", 9, null, 0, 0)!! == 4);
  _assert(__reg_match("[1-5a-]+", "123a--2oo", 9, null, 0, 0)!! == 7);
  _assert(__reg_match("[htps]+://", "https://", 8, null, 0, 0)!! == 8);
  _assert(__reg_match("[^\\s]+", "abc def", 7, null, 0, 0)!! == 3);
  _assert(__reg_match("[^fc]+", "abc def", 7, null, 0, 0)!! == 2);
  _assert(__reg_match("[^d\\sf]+", "abc def", 7, null, 0, 0)!! == 3);

  // Flags - case sensitivity 
  _assert(__reg_match("FO", "foo", 3, null, 0, 0)!! == NO_MATCH);
  _assert(__reg_match("FO", "foo", 3, null, 0, IGNORE_CASE)!! == 2);
  
  _assert(__reg_match_e("(?m)FO", "foo", 3, null, 0, 0) ==
    regex::UNEXPECTED_QUANTIFIER);
  _assert(__reg_match_e("(?m)x", "foo", 3, null, 0, 0) ==
    regex::UNEXPECTED_QUANTIFIER);

  _assert(__reg_match("fo", "foo", 3, null, 0, 0)!! == 2);
  _assert(__reg_match(".+", "foo", 3, null, 0, 0)!! == 3);
  _assert(__reg_match(".+k", "fooklmn", 7, null, 0, 0)!! == 4);
  _assert(__reg_match(".+k.", "fooklmn", 7, null, 0, 0)!! == 5);
  _assert(__reg_match("p+", "fooklmn", 7, null, 0, 0)!! == NO_MATCH);
  _assert(__reg_match("ok", "fooklmn", 7, null, 0, 0)!! == 4);
  _assert(__reg_match("lmno", "fooklmn", 7, null, 0, 0)!! == NO_MATCH);
  _assert(__reg_match("mn.", "fooklmn", 7, null, 0, 0)!! == NO_MATCH);
  _assert(__reg_match("o", "fooklmn", 7, null, 0, 0)!! == 2);
  _assert(__reg_match("^o", "fooklmn", 7, null, 0, 0)!! == NO_MATCH);
  _assert(__reg_match("^", "fooklmn", 7, null, 0, 0)!! == 0);
  _assert(__reg_match("n$", "fooklmn", 7, null, 0, 0)!! == 7);
  _assert(__reg_match("n$k", "fooklmn", 7, null, 0, 0)!! == NO_MATCH);
  _assert(__reg_match("l$", "fooklmn", 7, null, 0, 0)!! == NO_MATCH);
  _assert(__reg_match(".$", "fooklmn", 7, null, 0, 0)!! == 7);
  _assert(__reg_match("a?", "fooklmn", 7, null, 0, 0)!! == 0);
  _assert(__reg_match("^a*CONTROL", "CONTROL", 7, null, 0, 0)!! == 7);
  _assert(__reg_match("^[a]*CONTROL", "CONTROL", 7, null, 0, 0)!! == 7);
  _assert(__reg_match("^(a*)CONTROL", "CONTROL", 7, null, 0, 0)!! == 7);
  _assert(__reg_match("^(a*)?CONTROL", "CONTROL", 7, null, 0, 0)!! == 7);

  _assert(__reg_match_e("\\_", "abc", 3, null, 0, 0) == regex::INVALID_METACHARACTER);
  _assert(__reg_match_e("+", "fooklmn", 7, null, 0, 0) == regex::UNEXPECTED_QUANTIFIER);
  _assert(__reg_match("()+", "fooklmn", 7, null, 0, 0)!! == NO_MATCH);
  _assert(__reg_match_e("\\x", "12", 2, null, 0, 0) == regex::INVALID_METACHARACTER);
  _assert(__reg_match_e("\\xhi", "12", 2, null, 0, 0) == regex::INVALID_METACHARACTER);
  _assert(__reg_match("\\x20", "_ J", 3, null, 0, 0)!! == 2);
  _assert(__reg_match("\\x4A", "_ J", 3, null, 0, 0)!! == 3);
  _assert(__reg_match("\\d+", "abc123def", 9, null, 0, 0)!! == 6);

  // Balancing brackets 
  _assert(__reg_match_e("(x))", "fooklmn", 7, null, 0, 0) == regex::UNBALANCED_BRACKETS);
  
  _assert(__reg_match_e("(", "fooklmn", 7, null, 0, 0) == regex::UNBALANCED_BRACKETS);

  _assert(__reg_match("klz?mn", "fooklmn", 7, null, 0, 0)!! == 7);
  _assert(__reg_match("fa?b", "fooklmn", 7, null, 0, 0)!! == NO_MATCH);

  // Brackets & capturing
  _assert(__reg_match("^(te)", "tenacity subdues all", 20, caps, 10, 0)!! == 2);
  _assert(__reg_match("(bc)", "abcdef", 6, caps, 10, 0)!! == 3);
  _assert(__reg_match(".(d.)", "abcdef", 6, caps, 10, 0)!! == 5);
  _assert(__reg_match(".(d.)\\)?", "abcdef", 6, caps, 10, 0)!! == 5);
  _assert(caps[1].len == 2);
  _assert(string::memcmp(caps[1].ptr, "de", 2) == 0);
  _assert(__reg_match("(.+)", "123", 3, caps, 10, 0)!! == 3);
  _assert(__reg_match("(2.+)", "123", 3, caps, 10, 0)!! == 3);
  _assert(caps[1].len == 2);
  _assert(string::memcmp(caps[1].ptr, "23", 2) == 0);
  _assert(__reg_match("(.+2)", "123", 3, caps, 10, 0)!! == 2);
  _assert(caps[1].len == 2);
  _assert(string::memcmp(caps[1].ptr, "12", 2) == 0);

  _assert(__reg_match("(.*(2.))", "123", 3, caps, 10, 0)!! == 3);
  _assert(string::memcmp(caps[2].ptr, "23", 2) == 0);

  _assert(__reg_match("(.)(.)", "123", 3, caps, 10, 0)!! == 2);
  _assert(__reg_match("(\\d+)\\s+(\\S+)", "12 hi", 5, caps, 10, 0)!! == 5);
  _assert(__reg_match("ab(cd)+ef", "abcdcdef", 8, null, 0, 0)!! == 8);
  _assert(__reg_match("ab(cd)*ef", "abcdcdef", 8, null, 0, 0)!! == 8);
  _assert(__reg_match("ab(cd)+?ef", "abcdcdef", 8, null, 0, 0)!! == 8);
  _assert(__reg_match("ab(cd)+?.", "abcdcdef", 8, null, 0, 0)!! == 5);
  _assert(__reg_match("ab(cd)?", "abcdcdef", 8, null, 0, 0)!! == 4);
  // _assert(__reg_match_e("a(b)(cd)", "abcdcdef", 8, caps, 1, 0) == regex::CAPS_ARRAY_TOO_SMALL);
  _assert(__reg_match("(.+/\\d+\\.\\d+)\\.jpg$", "/foo/bar/12.34.jpg", 18, caps, 1, 0)!! == 18);
  _assert(__reg_match("(ab|cd).*\\.(xx|yy)", "ab.yy", 5, null, 0, 0)!! == 5);
  _assert(__reg_match(".*a", "abcdef", 6, null, 0, 0)!! == 1);
  _assert(__reg_match("(.+)c", "abcdef", 6, null, 0, 0)!! == 3);
  _assert(__reg_match("\\n", "abc\ndef", 7, null, 0, 0)!! == 4);
  _assert(__reg_match("b.\\s*\\n", "aa\r\nbb\r\ncc\r\n\r\n", 14, caps, 10, 0)!! == 8);

  // Greedy vs non-greedy 
  _assert(__reg_match(".+c", "abcabc", 6, null, 0, 0)!! == 6);
  _assert(__reg_match(".+?c", "abcabc", 6, null, 0, 0)!! == 3);
  _assert(__reg_match(".*?c", "abcabc", 6, null, 0, 0)!! == 3);
  _assert(__reg_match(".*c", "abcabc", 6, null, 0, 0)!! == 6);
  _assert(__reg_match("bc.d?k?b+", "abcabc", 6, null, 0, 0)!! == 5);

  // Branching 
  _assert(__reg_match("|", "abc", 3, null, 0, 0)!! == 0);
  _assert(__reg_match("|.", "abc", 3, null, 0, 0)!! == 1);
  _assert(__reg_match("x|y|b", "abc", 3, null, 0, 0)!! == 2);
  _assert(__reg_match("k(xx|yy)|ca", "abcabc", 6, null, 0, 0)!! == 4);
  _assert(__reg_match("k(xx|yy)|ca|bc", "abcabc", 6, null, 0, 0)!! == 3);
  _assert(__reg_match("(|.c)", "abc", 3, caps, 10, 0)!! == 3);
  _assert(caps[1].len == 2);
  _assert(string::memcmp(caps[1].ptr, "bc", 2) == 0);
  _assert(__reg_match("a|b|c", "a", 1, null, 0, 0)!! == 1);
  _assert(__reg_match("a|b|c", "b", 1, null, 0, 0)!! == 1);
  _assert(__reg_match("a|b|c", "c", 1, null, 0, 0)!! == 1);
  _assert(__reg_match("a|b|c", "d", 1, null, 0, 0)!! == NO_MATCH);

  // Optional match at the end of the string
  _assert(__reg_match("^.*c.?$", "abc", 3, null, 0, 0)!! == 3);
  _assert(__reg_match("^.*C.?$", "abc", 3, null, 0, IGNORE_CASE)!! == 3);
  _assert(__reg_match("bk?", "ab", 2, null, 0, 0)!! == 2);
  _assert(__reg_match("b(k?)", "ab", 2, null, 0, 0)!! == 2);
  _assert(__reg_match("b[k-z]*", "ab", 2, null, 0, 0)!! == 2);
  _assert(__reg_match("ab(k|z|y)*", "ab", 2, null, 0, 0)!! == 2);
  _assert(__reg_match("[b-z].*", "ab", 2, null, 0, 0)!! == 2);
  _assert(__reg_match("(b|z|u).*", "ab", 2, null, 0, 0)!! == 2);
  _assert(__reg_match("ab(k|z|y)?", "ab", 2, null, 0, 0)!! == 2);
  _assert(__reg_match(".*", "ab", 2, null, 0, 0)!! == 2);
  _assert(__reg_match(".*$", "ab", 2, null, 0, 0)!! == 2);
  _assert(__reg_match("a+$", "aa", 2, null, 0, 0)!! == 2);
  _assert(__reg_match("a*$", "aa", 2, null, 0, 0)!! == 2);
  _assert(__reg_match( "a+$" ,"Xaa", 3, null, 0, 0)!! == 3);
  _assert(__reg_match( "a*$" ,"Xaa", 3, null, 0, 0)!! == 3);

  // Ignore case flag 
  _assert(__reg_match("[a-h]+", "abcdefghxxx", 11, null, 0, 0)!! == 8);
  _assert(__reg_match("[A-H]+", "ABCDEFGHyyy", 11, null, 0, 0)!! == 8);
  _assert(__reg_match("[a-h]+", "ABCDEFGHyyy", 11, null, 0, 0)!! == NO_MATCH);
  _assert(__reg_match("[A-H]+", "abcdefghyyy", 11, null, 0, 0)!! == NO_MATCH);
  _assert(__reg_match("[a-h]+", "ABCDEFGHyyy", 11, null, 0, IGNORE_CASE)!! == 8);
  _assert(__reg_match("[A-H]+", "abcdefghyyy", 11, null, 0, IGNORE_CASE)!! == 8);

  {
    // Example: HTTP request
    char *request = " GET /index.html HTTP/1.0\r\n\r\n";
    // Match[4] caps;

    if (__reg_match("^\\s*(\\S+)\\s+(\\S+)\\s+HTTP/(\\d)\\.(\\d)", ((ZString)request).str_view(), (int)string::strlen(request), caps, 5, 0)!! > 0) {
      io::printf("Method: [%.*s], URI: [%.*s]\n", caps[1].len, _str(caps[1].ptr), caps[2].len, _str(caps[2].ptr));
    } else {
      io::printf("Error parsing [%s]\n", _str(request));
    }

    _assert(caps[2].len == 11);
    _assert(string::memcmp(caps[2].ptr, "/index.html", caps[2].len) == 0);
  }

  {
    // Example: string replacement 
    String s = __reg_replace("({{.+?}})", "Good morning, {{foo}}. How are you, {{bar}}?", "Bob")!!;
    warn("%s", s);
    _assert(string::strncmp(s.ptr, "Good morning, Bob. How are you, Bob?", s.len) == 0);
    s.free(mem);
  }

  {
    // Example: find all URLs in a string 
    String str =
      "<img src=\"HTTPS://FOO.COM/x?b#c=tab1\"/>   <a href=\"http://cesanta.com\">some link</a>";

    String regex = "((https?://)[^\\s/'\"<>]+/?[^\\s'\"<>]*)";
    // Match[2] caps;
    int i;
    int j = 0;
    int str_len = (int) str.len;

    while (j < str_len &&
           (i = __reg_match(regex, (String)str[j..], str_len - j, caps, 3, IGNORE_CASE)!!) > 0) {
      io::printf("Found URL: [%.*s]\n", caps[1].len, _str(caps[1].ptr));
      j += i;
    }
  }

  {
    // Example more complex regular expression 
    String str = "aa 1234 xy\nxyz";
    String regex = "aa ([0-9]*) *([x-z]*)\\s+xy([yz])";
    // Match[3] caps;
    _assert(__reg_match(regex, str, (int)str.len, caps, 4, 0)!! > 0);
    _assert(caps[1].len == 4);
    _assert(caps[2].len == 2);
    _assert(caps[3].len == 1);
    warn("[%.*s] %d", caps[3].len, _str(caps[3].ptr), caps[3].len);
    _assert(caps[3].ptr[0] == 'z');
  }

}
