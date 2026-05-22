// regex.c3

// Nomota <hiongun@gmail.com>; MIT License

module ext::regex;

import std::collections::list;
import slre;
import std::io;
import ext::mem;

const int MAX_GROUP = 10;
struct RegEx {
    slre::RegexInfo info;
    slre::SlreCap[MAX_GROUP] caps;
    String expr;
    String str;
}

struct RegMatch {
    String s;
    int pos;
    int len;
}

faultdef
    NO_MATCH,
    UNEXPECTED_QUANTIFIER,
    UNBALANCED_BRACKETS,
    INTERNAL_ERROR,
    INVALID_CHARACTER_SET,
    INVALID_METACHARACTER,
    CAPS_ARRAY_TOO_SMALL,
    TOO_MANY_BRANCHES,
    TOO_MANY_BRACKETS,
    RANGE_ERROR,
    EMPTY_EXPR,
    EMPTY_STR,
    GENERAL_ERROR;

macro void warn(String fmt, args...)
{
  io::printf("%s,%s: ", $$FILE, $$LINE); io::printfn(fmt, ...args);
}

tlocal LocalAllocator allocx = {};

fn fault err_fault(int err) @private
{
    switch (err) {
        case slre::NO_MATCH:              return NO_MATCH;
        case slre::UNEXPECTED_QUANTIFIER: return UNEXPECTED_QUANTIFIER;
        case slre::UNBALANCED_BRACKETS:   return UNBALANCED_BRACKETS;
        case slre::INTERNAL_ERROR:        return INTERNAL_ERROR;
        case slre::INVALID_CHARACTER_SET: return INVALID_CHARACTER_SET;
        case slre::INVALID_METACHARACTER: return INVALID_METACHARACTER;
        case slre::CAPS_ARRAY_TOO_SMALL:  return CAPS_ARRAY_TOO_SMALL;
        case slre::TOO_MANY_BRANCHES:     return TOO_MANY_BRANCHES;
        case slre::TOO_MANY_BRACKETS:     return TOO_MANY_BRACKETS;
    }
    return GENERAL_ERROR;
}

fn String? brace(Allocator alloc, String expr) @private
{
    allocx = alloc;
    String x = (String)allocx.alloc_array(char, expr.len+2)!;
    x[0] = '(';
    x[expr.len+1] = ')';
    x[1:expr.len] = expr[0:expr.len];
    return x;
}

fn RegEx*? new_compile(Allocator alloc, String expr, bool ignore_case = false) 
{
    if (expr.len == 0) {
        return EMPTY_EXPR~;
    }
    allocx = alloc;
    RegEx* reg = allocx.alloc(RegEx)!;

    reg.expr = brace(alloc, expr)!;
    
    // Initialize RegexInfo
    reg.info.flags = ignore_case ? slre::IGNORE_CASE: 0;
    reg.info.num_brackets = 0;
    reg.info.num_branches = 0;
    reg.info.num_caps = (int)reg.caps.len;
    reg.info.caps = &reg.caps;
    
    int err = slre::compile((char*)&reg.expr[0], (int)reg.expr.len, &reg.info);
    if (err < 0) {
        allocx.free(reg);
        return err_fault(err)~;
    }
    
    return reg;
}

fn void RegEx.free(&self)
{
    self.expr.free(allocx);
    allocx.free(self);
}

fn int? RegEx.match(&self, String str, int* start = null, int* len = null)
{
    if (str.len == 0) {
        return EMPTY_STR~;
    }
    self.str = str;

    foreach (&cap: self.caps) {
        cap.ptr = null;
        cap.len = -1;
    }

    int result = slre::match(self.str.ptr, (int)self.str.len, &self.info);
    // warn("expr:%s, str:%s, result:%d", self.expr, str, result);
    if (result < 0) {
        if (result == slre::NO_MATCH) return result;
        return err_fault(result)~;
    }
    
    if (start != null) {
        *start = (int)(self.caps[0].ptr - self.str.ptr);
    }
    if (len != null) {
        *len = self.caps[0].len;
    }
/*
    foreach (&cap: self.caps) {
        if (cap.ptr != null && cap.len > 0) {
            warn("(%s, %d)", (String)cap.ptr[0:cap.len], cap.len);
        }
    }
    
    warn("expr:%s, str:%s, result:%d, start:%d, len:%d", self.expr, str, result, *start, *len);
*/
    return result;    
}

fn RegMatch? RegEx.group(&self, int idx)
{
    if (idx < 0 || idx >= self.caps.len) return RANGE_ERROR~;
    if (self.caps[idx].ptr == null) return RANGE_ERROR~;
    
    return {
        (String) self.caps[idx].ptr[0: self.caps[idx].len],
        (int)(self.caps[idx].ptr - self.str.ptr),
        self.caps[idx].len
    };
}

fn List{int[2]} RegEx.find_all(&self, String str)
{
    List{int[2]} lst;
    lst.init(mem);

    int pos = 0;
    SlreCap* cap = &self.caps[0];
    while (pos < str.len) {
        int n = slre::match(&str[pos], str.len-pos, &self.info);
        // warn("n:%d, expr:%s, str:%s", n, self.expr, str);
        if (n > 0) {
            int[2] p = {
                pos + (int)(cap.ptr - &str[pos]),
                cap.len
            };
            lst.push(p);
            pos = p[0] + p[1];
            // warn("%d,%d", p[0], p[1]);
            continue;
        }
        if (n == 0) {
            pos += 1;
        } else {
            break;
        }
    }
    
    return lst;
}

<*
 should properly free the returned String
*>
fn String? RegEx.replace(&self, Allocator allocx, String str, String sub, int n = 0)
{
    DString result;
    result.init(allocx);
    defer result.free();
    
    List{int[2]} lst = self.find_all(str);
    defer lst.free();
   
    int pos = 0;
    foreach (i, p: lst) {
        result.append(str[pos..p[0]-1]);
        // warn("result: %s", result.str_view());
        result.append(sub);
        // warn("result: %s", result.str_view());

        pos = p[0]+p[1];
        if (n > 0 && i+1 == n) break;
    }
    if (pos < str.len) {
        result.append(str[pos..]);
        // warn("result: %s", result.str_view());
    }

    return result.copy_str(allocx);
}

<*
 should properly free returned List
*>
fn List{String}? RegEx.split(&self, Allocator allocx, String str, int n = 0)
{
    List{String} result;
    result.init(allocx);

    List{int[2]} lst = self.find_all(str);
    defer lst.free();
   
    int pos = 0;
    foreach (i, p: lst) {
        result.push(str[pos..p[0]-1]);
    
        pos = p[0] + p[1];
        if (n > 0 && i+1 == n) break;
    }
    if (pos < str.len) {
        result.push(str[pos..]);
    }

    return result;
}


fn bool? reg_match(String expr, String str, int* start = null, int* len = null, bool ignore_case=false)
{
    RegEx* reg = new_compile(mem, expr, ignore_case)!; 
    defer reg.free();
    return reg.match(str, start, len) >= 0;
}

fn String? reg_replace(Allocator allocx, String expr, String str, String sub, int n = 0, bool ignore_case=false)
{
    RegEx* reg = new_compile(allocx, expr, ignore_case)!;
    defer reg.free();
    return reg.replace(allocx, str, sub, n);
}

fn List{String}? reg_split(Allocator allocx, String expr, String str, int n = 0, bool ignore_case=false)
{
    RegEx* reg = new_compile(allocx, expr, ignore_case)!;
    defer reg.free();
    return reg.split(allocx, str, n);
}
