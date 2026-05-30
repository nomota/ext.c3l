// slre.c3

module slre;

import std::io;
import c::string;
import c::stdio;
import c::stdlib;

struct SlreCap {
  char *ptr;
  int len;
}

const int IGNORE_CASE = 1;

const int NO_MATCH =              -1;
const int UNEXPECTED_QUANTIFIER = -2;
const int UNBALANCED_BRACKETS =   -3;
const int INTERNAL_ERROR =        -4;
const int INVALID_CHARACTER_SET = -5;
const int INVALID_METACHARACTER = -6;
const int CAPS_ARRAY_TOO_SMALL =  -7;
const int TOO_MANY_BRANCHES =     -8;
const int TOO_MANY_BRACKETS =     -9;

const int MAX_BRANCHES = 100;
const int MAX_BRACKETS = 100;

macro void dbg(String fmt, args...)
{
  // io::printf("%s,%s: ", $$FILE, $$LINE); io::printf(fmt, ...args);
}

macro String _str(char* s) 
{
  return ((ZString)s).str_view();
}

macro array_size(ar) 
{
    return ar.len;
}

struct BracketPair {
  char *ptr;  /* Points to the first char after '(' in regex  */
  int len;          /* Length of the text between '(' and ')'       */
  int branches;     /* Index in the branches array for this pair    */
  int num_branches; /* Number of '|' in this bracket pair           */
}

struct Branch {
  int bracket_index;    /* index for 'BracketPair brackets' */
                        /* array defined below                      */
  char *schlong;  /* points to the '|' character in the regex */
}

struct RegexInfo {
  /*
   * Describes all bracket pairs in the regular expression.
   * First entry is always present, and grabs the whole regex.
   */
  BracketPair[MAX_BRACKETS] brackets;
  int num_brackets;

  /*
   * Describes alternations ('|' operators) in the regular expression.
   * Each branch falls into a specific branch pair.
   */
  Branch[MAX_BRANCHES] branches;
  int num_branches;

  /* Array of captures provided by the user */
  SlreCap *caps;
  int num_caps;

  /* E.g. IGNORE_CASE. See enum below */
  int flags;
}


macro bool is_metacharacter(char *s) {
  const char *META = "^$().[]*+?|\\Ssdbfnrtvw";
  return string::strchr(META, *s) != null;
}

macro int __op_len(char *re) {
  return (re[0] == '\\' && re[1] == 'x') ? 4 : (re[0] == '\\') ? 2 : 1;
}

macro int op_len(char *re) {
  return re[0] == '\\' ? (re[1] == 'x' ? 4 : 2) : 1;
}

macro int __set_len(char *re, int re_len) {
  int len = 0;

  while (len < re_len && re[len] != ']') {
    len += op_len(re + len);
  }

  return len <= re_len ? len + 1 : -1;
}

macro int set_len(char *re, int re_len) {
  int len = 0;

  while (len < re_len) {
    len += op_len(re + len);
    if ( re[len] == ']' ) return len + 1;
  }

  return -1;
}

macro int get_op_len(char *re, int re_len) {
  return re[0] == '[' ? set_len(re + 1, re_len - 1) + 1 : op_len(re);
}

macro int __get_op_len(char *re, int re_len) {
  return re[0] == '[' ? set_len(re + 1, re_len - 1) : op_len(re);
}

macro bool is_quantifier(char *re) {
  return re[0] == '*' || re[0] == '+' || re[0] == '?';
}

macro bool isdigit(char c) {
  return '0' <= c && c <= '9';
}

macro bool isword(char c) {
  return ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z') || c == '_';
}

macro bool isxdigit(char c) {
  return ('0' <= c && c <= '9') || ('A' <= c && c <= 'F') || ('a' <= c && c <= 'f');
}

macro bool isspace(char c) {
  return ' ' == c || c == '\t' || c == '\r' || c == '\n';
}

macro int toi(int x) {
  return isdigit((char)x) ? (int)(x - '0') : (int)(x - 'W');
}

macro char tolower(char c) {
  if ('A' <= c && c <= 'Z') return 'a'+(c-'A');
  return c;
}

macro int hextoi(char *s) {
  return (toi(tolower(s[0])) << 4) | toi(tolower(s[1]));
}

fn int match_op(char *re, char *s, RegexInfo *info) {
  int result = 0;
  switch (*re) {
    case '\\':
      /* Metacharacters */
      switch (re[1]) {
        case 'S': if (isspace(*s)) return NO_MATCH; result++;
        case 's': if (!isspace(*s)) return NO_MATCH; result++;
        case 'd': if (!isdigit(*s)) return NO_MATCH; result++;
        case 'w': if (!isword(*s)) return NO_MATCH; result++;
        case 'b': if (*s != '\b') return NO_MATCH; result++;
        case 'f': if (*s != '\f') return NO_MATCH; result++;
        case 'n': if (*s != '\n') return NO_MATCH; result++;
        case 'r': if (*s != '\r') return NO_MATCH; result++;
        case 't': if (*s != '\t') return NO_MATCH; result++;
        case 'v': if (*s != '\v') return NO_MATCH; result++;

        case 'x':
          /* Match byte, \xHH where HH is hexadecimal byte representaion */
          if (hextoi(re + 2) != *s) return NO_MATCH;
          result++;

        default:
          /* Valid metacharacter check is done in bar() */
          if (re[1] != s[0]) return NO_MATCH;
          result++;
      }

    case '|': if (true) return INTERNAL_ERROR;
    case '$': if (true) return NO_MATCH;
    case '.': result++;

    default:
      if (info.flags & IGNORE_CASE) {
        if (tolower(*re) != tolower(*s)) return NO_MATCH;
      } else {
        if (*re != *s) return NO_MATCH;
      }
      result++;
  }

  return result;
}

fn int match_set(char *re, int re_len, char *s, RegexInfo *info) {
  int len = 0;
  int result = -1;
  bool invert = (re[0] == '^');

  if (invert) { re++; re_len--; }

  while (len <= re_len && re[len] != ']' && result <= 0) {
    /* Support character range */
    if (re[len] != '-' && re[len + 1] == '-' && re[len + 2] != ']' &&
        re[len + 2] != '\0') {
      result = info.flags & IGNORE_CASE ?
        (int)(tolower(*s) >= tolower(re[len]) && tolower(*s) <= tolower(re[len + 2])) :
        (int)(*s >= re[len] && *s <= re[len + 2]);
      len += 3;
    } else {
      result = match_op((char *) re + len, (char *) s, info);
      len += op_len(re + len);
    }
  }
  return (!invert && result > 0) || (invert && result <= 0) ? 1 : -1;
}

fn int match_in(char *re, int re_len, char *s, int s_len, RegexInfo *info, int bi) {
  /* i is offset in re, j is offset in s, bi is brackets index */
  int i = 0;
  int j = 0;
  int n = 0;
  int step;

  for (i = 0; i < re_len && j <= s_len; i += step) {

    /* Handle quantifiers. Get the length of the chunk. */
    step = re[i] == '(' ? info.brackets[bi + 1].len + 2 :
      get_op_len(re + i, re_len - i);

    dbg("[%.*s] [%.*s] re_len=%d step=%d i=%d j=%d\n",
         re_len - i, _str(re + i), s_len - j, _str(s + j), re_len, step, i, j);

    if (is_quantifier(&re[i])) return UNEXPECTED_QUANTIFIER;
    if (step <= 0) return INVALID_CHARACTER_SET;

    if (i + step < re_len && is_quantifier(re + i + step)) {
      dbg("QUANTIFIER: [%.*s]%c [%.*s]\n", step, _str(re + i),
           re[i + step], s_len - j, _str(s + j));
      if (re[i + step] == '?') {
        int result = match_in(re + i, step, s + j, s_len - j, info, bi);
        j += result > 0 ? result : 0;
        i++;
      } else if (re[i + step] == '+' || re[i + step] == '*') {
        int j2 = j;
        int nj = j;
        int n1;
        int n2 = -1;
        int ni;
        int non_greedy = 0;

        /* Points to the regexp code after the quantifier */
        ni = i + step + 1;
        if (ni < re_len && re[ni] == '?') {
          non_greedy = 1;
          ni++;
        }

        do {
          if ((n1 = match_in(re + i, step, s + j2, s_len - j2, info, bi)) > 0) {
            j2 += n1;
          }
          if (re[i + step] == '+' && n1 < 0) break;

          if (ni >= re_len) {
            /* After quantifier, there is nothing */
            nj = j2;
          } else if ((n2 = match_in(re + ni, re_len - ni, s + j2, s_len - j2, info, bi)) >= 0) {
            /* Regex after quantifier matched */
            nj = j2 + n2;
          }
          if (nj > j && non_greedy) break;
        } while (n1 > 0);

        /*
         * Even if we found one or more pattern, this branch will be executed,
         * changing the next captures.
         */
        if (n1 < 0 && n2 < 0 && re[i + step] == '*' &&
            (n2 = match_in(re + ni, re_len - ni, s + j, s_len - j, info, bi)) > 0) {
          nj = j + n2;
        }

        dbg("STAR/PLUS END: %d %d %d %d %d\n", j, nj, re_len - ni, n1, n2);
        if (re[i + step] == '+' && nj == j) return NO_MATCH;

        /* If while loop body above was not executed for the * quantifier,  */
        /* make sure the rest of the regex matches                          */
        if (nj == j && ni < re_len && n2 < 0) return NO_MATCH;

        /* Returning here cause we've matched the rest of RE already */
        return nj;
      }
      continue;
    }

    if (re[i] == '[') {
      n = match_set(re + i + 1, re_len - (i + 2), s + j, info);
      dbg("SET %.*s [%.*s] . %d\n", step, _str(re + i), s_len - j, _str(s + j), n);
      if (n <= 0) return NO_MATCH;
      j += n;
    } else if (re[i] == '(') {
      n = NO_MATCH;
      bi++;
      if (bi >= info.num_brackets) return INTERNAL_ERROR;
      dbg("CAPTURING [%.*s] [%.*s] [%s]\n",
           step, _str(re + i), s_len - j, _str(s + j), _str(re + i + step));

      if (re_len - (i + step) <= 0) {
        /* Nothing follows brackets */
        n = proc_branch(s + j, s_len - j, info, bi);
      } else {
        int j2;
        for (j2 = 0; j2 <= s_len - j; j2++) {
          if ((n = proc_branch(s + j, s_len - (j + j2), info, bi)) >= 0 &&
              match_in(re + i + step, re_len - (i + step),
                  s + j + n, s_len - (j + n), info, bi) >= 0) break;
        }
      }

      dbg("CAPTURED [%.*s] [%.*s]:%d\n", step, _str(re + i), s_len - j, _str(s + j), n);
      if (n < 0) return n;
      if (info.caps != null && n > 0) {
        info.caps[bi - 1].ptr = s + j;
        info.caps[bi - 1].len = n;
      }
      j += n;
    } else if (re[i] == '^') {
      if (j != 0) return NO_MATCH;
    } else if (re[i] == '$') {
      if (j != s_len) return NO_MATCH;
    } else {
      if (j >= s_len) return NO_MATCH;
      n = match_op((char *) (re + i), (char *) (s + j), info);
      if (n <= 0) return n;
      j += n;
    }
  }

  return j;
}

/* Process branch points */
fn int proc_branch(char *s, int s_len, RegexInfo *info, int bi) {
  BracketPair *b = &info.brackets[bi];
  int i = 0;
  int len;
  int result;
  char *p;

  do {
    p = (i == 0) ? b.ptr : info.branches[b.branches + i - 1].schlong + 1;
    len = (b.num_branches == 0) ? b.len :
      (i == b.num_branches) ? (int) (b.ptr + b.len - p) :
      (int) (info.branches[b.branches + i].schlong - p);
    dbg("%d %d [%.*s] [%.*s]\n", bi, i, len, _str(p), s_len, _str(s));
    result = match_in(p, len, s, s_len, info, bi);
    dbg("proc_branch <- %d\n", result);
  } while (result <= 0 && i++ < b.num_branches);  /* At least 1 iteration */

  return result;
}

fn int match(char *s, int s_len, RegexInfo *info) {
  int result = -1;
  bool is_anchored = (info.brackets[0].ptr[0] == '^') || (info.brackets[0].ptr[0] == '(' && info.brackets[0].ptr[1] == '^');

  for (int i = 0; i <= s_len; i++) {
    result = proc_branch(s + i, s_len - i, info, 0);
    if (result >= 0) {
      result += i;
      break;
    }
    if (is_anchored) break;
  }

  return result;
}

fn void setup_branch_points(RegexInfo *info) {
  Branch tmp;

  /* First, sort branches. Must be stable, no qsort. Use bubble algo. */
  for (int i = 0; i < info.num_branches; i++) {
    for (int j = i + 1; j < info.num_branches; j++) {
      if (info.branches[i].bracket_index > info.branches[j].bracket_index) {
        tmp = info.branches[i];
        info.branches[i] = info.branches[j];
        info.branches[j] = tmp;
      }
    }
  }

  /*
   * For each bracket, set their branch points. This way, for every bracket
   * (i.e. every chunk of regex) we know all branch points before matching.
   */
  int j = 0;
  for (int i = 0; i < info.num_brackets; i++) {
    info.brackets[i].num_branches = 0;
    info.brackets[i].branches = j;
    while (j < info.num_branches && info.branches[j].bracket_index == i) {
      info.brackets[i].num_branches++;
      j++;
    }
  }
}

fn int compile(char *re, int re_len, RegexInfo *info) {
  int i;
  int step;
  int depth = 0;

  /* First bracket captures everything */
  info.brackets[0].ptr = re;
  info.brackets[0].len = re_len;
  info.num_brackets = 1;

  /* Make a single pass over regex string, memorize brackets and branches */
  for (i = 0; i < re_len; i += step) {
    step = get_op_len(re + i, re_len - i);
    if (step <= 0) return UNBALANCED_BRACKETS;
    if (re[i] == '|') {
      if (info.num_branches >= (int) array_size(info.branches)) return TOO_MANY_BRANCHES;
      info.branches[info.num_branches].bracket_index =
        (info.brackets[info.num_brackets - 1].len == -1) ?
        info.num_brackets - 1 : depth;
      info.branches[info.num_branches].schlong = &re[i];
      info.num_branches++;
    } else if (re[i] == '\\') {
      dbg("i:%d, re_len:%d\n", i, re_len);
      if (i >= (re_len - 1)) return INVALID_METACHARACTER;
      if (i >= (re_len - 2)) {
        if (re[i+1] == ')') {
          if (info.brackets[info.num_brackets-1].len == -1) {
            return INVALID_METACHARACTER;
          }
        }
      }
            
      if (re[i + 1] == 'x') {
        /* Hex digit specification must follow */
        if (re[i + 1] == 'x' && i >= re_len - 3) return INVALID_METACHARACTER;
        if (re[i + 1] ==  'x' && !(isxdigit(re[i + 2]) && isxdigit(re[i + 3]))) return INVALID_METACHARACTER;
      } else {
        if (!is_metacharacter((char *) re + i + 1)) return INVALID_METACHARACTER;
      }
    } else if (re[i] == '(') {
      if (info.num_brackets >= (int) array_size(info.brackets)) return TOO_MANY_BRACKETS;
      depth++;  /* Order is important here. Depth increments first. */
      info.brackets[info.num_brackets].ptr = re + i + 1;
      info.brackets[info.num_brackets].len = -1;
      info.num_brackets++;
      if (info.num_caps > 0 && info.num_brackets - 1 > info.num_caps) return CAPS_ARRAY_TOO_SMALL;
    } else if (re[i] == ')') {
      int ind = (info.brackets[info.num_brackets - 1].len == -1) ?
        info.num_brackets - 1 : depth;
      info.brackets[ind].len = (int) (&re[i] - info.brackets[ind].ptr);
      dbg("SETTING BRACKET %d [%.*s]\n",
           ind, info.brackets[ind].len, _str(info.brackets[ind].ptr));
      depth--;
      if (depth < 0) return UNBALANCED_BRACKETS;
      if (i > 0 && re[i - 1] == '(') NO_MATCH;
    }
  }

  if (depth != 0) return UNBALANCED_BRACKETS;
  setup_branch_points(info);

  return 0; // ok
  // return baz(s, s_len, info);
}

fn int reg_match(char *regexp, char *s, int s_len, SlreCap *caps, int num_caps, int flags) {
  RegexInfo info;

  /* Initialize info structure */
  info.flags = flags;
  info.num_brackets = 0;
  info.num_branches = 0;
  info.num_caps = num_caps;
  info.caps = caps;

  dbg("========================> [%s] [%.*s]\n", _str(regexp), s_len, _str(s));
  int a = compile(regexp, (int) string::strlen(regexp), &info);
  if (a < 0) return a;
  int b = match(s, s_len, &info);
  return b;
}

/* Regex must have exactly one bracket pair */
fn char *reg_replace(char *regex, char *buf, char *sub) {
  char *s = null;
  int n;
  int n1;
  int n2;
  int n3;
  int len = (int)string::strlen(buf);
  SlreCap cap = { null, 0 };

  do {
    int s_len = (s == null) ? 0 : (int)string::strlen(s);
    if ((n = reg_match(regex, buf, len, &cap, 1, 0)) > 0) {
      n1 = (int)(cap.ptr - &buf[0]);
      n2 = (int)string::strlen(sub);
      n3 = (int) (&buf[n] - &cap.ptr[cap.len]);
    } else {
      n1 = len;
      n2 = 0;
      n3 = 0;
    }
    s = (char *) stdlib::realloc(s, (sz) s_len + n1 + n2 + n3 + 1);
    string::memcpy(s + s_len, buf, n1);
    string::memcpy(s + s_len + n1, sub, n2);
    string::memcpy(s + s_len + n1 + n2, cap.ptr + cap.len, n3);
    s[s_len + n1 + n2 + n3] = '\0';

    buf += n > 0 ? n : len;
    len -= n > 0 ? n : len;
  } while (len > 0);

  return s;
}
