// regex_example.c3
// C3 RegEx Library Usage Examples

module regex_example;

import std::collections::list;
import std::io;
import ext::regex;

fn void? example_basic_match()
{
    io::printn("\n=== 1. Basic Pattern Matching ===");
    
    // Simple pattern matching
    String text = "Hello World 2026";
    String pattern = "World";
    
    int start, len;
    bool matched = regex::reg_match(pattern, text, &start, &len)!;
    
    if (matched) {
        io::printfn("Pattern '%s' found!", pattern);
        io::printfn("Position: %d, Length: %d", start, len);
        io::printfn("Matched string: '%s'", text[start:len]);
    } else {
        io::printn("No match found");
    }
}

fn void? example_regex_object()
{
    io::printn("\n=== 2. RegEx Object Reuse Example ===");
    
    // Create and reuse RegEx object
    RegEx* reg = regex::new_compile(mem, "\\d+")!;
    defer reg.free();
    
    String[] texts = {
        "Price is $1000",
        "Phone: 010-1234-5678",
        "No numbers here"
    };
    
    foreach (text : texts) {
        int start, len;
        int result = reg.match(text, &start, &len)!;
        
        if (result >= 0) {
            io::printfn("'%s' → Number found: '%s' (position: %d)", 
                       text, text[start:len], start);
        } else {
            io::printfn("'%s' → No numbers", text);
        }
    }
}

fn void? example_groups()
{
    io::printn("\n=== 3. Capture Groups Example ===");
    
    // Email address parsing
    RegEx* reg = regex::new_compile(mem, "(\\w+)@(\\w+\\.\\w+)")!;
    defer reg.free();
    
    String email = "user@example.com";
    
    int result = reg.match(email)!;
    if (result >= 0) {
        io::printfn("Email: %s", email);
        
        // Full match (group 0)
        RegMatch full_match = reg.group(0)!;
        io::printfn("  Full: '%s'", full_match.s);
        
        // Username (group 1)
        RegMatch username = reg.group(1)!;
        io::printfn("  Username: '%s'", username.s);
        
        // Domain (group 2)
        RegMatch domain = reg.group(2)!;
        io::printfn("  Domain: '%s'", domain.s);
    }
}

fn void? example_find_all()
{
    io::printn("\n=== 4. Find All Matches Example ===");
    
    RegEx* reg = regex::new_compile(mem, "\\d+")!;
    defer reg.free();
    
    String text = "Order: 12345, Amount: $50000, Quantity: 3 items";
    
    List{int[2]} matches = reg.find_all(text);
    defer matches.free();
    
    io::printfn("Text: %s", text);
    io::printfn("Numbers found: %d", matches.len());
    
    foreach (i, pos : matches) {
        String num = text[pos[0]:pos[1]];
        io::printfn("  %d. '%s' (position: %d)", i+1, num, pos[0]);
    }
}

fn void? example_replace()
{
    io::printn("\n=== 5. String Replacement Example ===");
    
    // Replace all digits with '*'
    String text = "Phone: 010-1234-5678";
    String pattern = "\\d";
    String replacement = "*";
    
    String result = regex::reg_replace(mem, pattern, text, replacement)!;
    defer result.free(mem);
    
    io::printfn("Original: %s", text);
    io::printfn("Replaced: %s", result);
    
    // Replace only first 3 matches
    String result2 = regex::reg_replace(mem, pattern, text, replacement, 3)!;
    defer result2.free(mem);
    
    io::printfn("First 3 replaced: %s", result2);
}

fn void? example_replace_words()
{
    io::printn("\n=== 6. Word Replacement Example ===");
    
    String text = "I love cats. Cats are cute. CATS!";
    String pattern = "[Cc]ats?";
    String replacement = "dogs";
    
    String result = regex::reg_replace(mem, pattern, text, replacement)!;
    defer result.free(mem);
    
    io::printfn("Original: %s", text);
    io::printfn("Replaced: %s", result);
}

fn void? example_split()
{
    io::printn("\n=== 7. String Split Example ===");
    
    // Split by whitespace
    String text = "apple banana cherry date elderberry";
    String pattern = " ";
    
    List{String} words = regex::reg_split(mem, pattern, text)!;
    defer words.free();
    
    io::printfn("Text: %s", text);
    io::printfn("Word count: %d", words.len());
    
    foreach (i, word : words) {
        io::printfn("  %d. '%s'", i+1, word);
    }
}

fn void? example_split_delimiters()
{
    io::printn("\n=== 8. Split by Multiple Delimiters ===");
    
    // Split by comma, semicolon, or space
    String text = "apple,banana;cherry date,elderberry";
    String pattern = "[,; ]+";
    
    List{String} items = regex::reg_split(mem, pattern, text)!;
    defer items.free();
    
    io::printfn("Text: %s", text);
    io::printn("Items:");
    
    foreach (i, item : items) {
        io::printfn("  %d. '%s'", i+1, item);
    }
}

fn void? example_ignore_case()
{
    io::printn("\n=== 9. Case-Insensitive Matching ===");
    
    String text = "Hello WORLD hello World";
    String pattern = "hello";
    
    // Case-sensitive (default)
    bool matched1 = regex::reg_match(pattern, text)!;
    io::printfn("Case-sensitive: %s", matched1 ? "Matched" : "No match");
    
    // Case-insensitive
    bool matched2 = regex::reg_match(pattern, text, null, null, true)!;
    io::printfn("Case-insensitive: %s", matched2 ? "Matched" : "No match");
    
    // Find all "hello" (case-insensitive)
    RegEx* reg = regex::new_compile(mem, pattern, true)!;
    defer reg.free();
    
    List{int[2]} matches = reg.find_all(text);
    defer matches.free();
    
    io::printfn("\nPatterns found in '%s':", text);
    foreach (i, pos : matches) {
        io::printfn("  %d. '%s' (position: %d)", 
                   i+1, text[pos[0]:pos[1]], pos[0]);
    }
}

fn void? example_validation()
{
    io::printn("\n=== 10. Input Validation Example ===");
    
    // Email validation
    RegEx* email_reg = regex::new_compile(mem, "^\\w+@(\\w+\\.)+\\w+$")!;
    defer email_reg.free();
    
    String[] emails = {
        "user@example.com",
        "invalid.email",
        "test@domain.co.kr",
        "@missing.com"
    };
    
    io::printn("Email validation:");
    foreach (email : emails) {
        int result = email_reg.match(email)!;
        io::printfn("  '%s': %s", email, 
                   result >= 0 ? "✓ Valid" : "✗ Invalid");
    }
    
    // Phone number validation
    // \d{3} not supported
    RegEx* phone_reg = regex::new_compile(mem, "^\\d\\d\\d-\\d\\d\\d\\d-\\d\\d\\d\\d$")!;
    defer phone_reg.free();
    
    String[] phones = {
        "010-1234-5678",
        "02-123-4567",
        "01012345678",
        "010-123-456"
    };
    
    io::printn("\nPhone validation (010-xxxx-xxxx format):");
    foreach (phone : phones) {
        int result = phone_reg.match(phone)!;
        io::printfn("  '%s': %s", phone, 
                   result >= 0 ? "✓ Valid" : "✗ Invalid");
    }
}

fn void? example_url_parsing()
{
    io::printn("\n=== 11. URL Parsing Example ===");
    
    // Simple URL parsing
    RegEx* reg = regex::new_compile(mem, "(https?)://([^/]+)(/.+)?")!;
    defer reg.free();
    
    String url = "https://www.example.com/path/to/page";
    
    int result = reg.match(url)!;
    if (result >= 0) {
        io::printfn("URL: %s", url);
        
        RegMatch protocol = reg.group(1)!;
        io::printfn("  Protocol: %s", protocol.s);
        
        RegMatch domain = reg.group(2)!;
        io::printfn("  Domain: %s", domain.s);
        
        // Group 3 is optional, so error handling needed
        RegMatch? path = reg.group(3);
        if (try path) {
            io::printfn("  Path: %s", path.s);
        }
    }
}

fn void? example_log_parsing()
{
    io::printn("\n=== 12. Log Parsing Example ===");
    
    // Log format: [time] level: message
    // \d{2} not suported
    RegEx* reg = regex::new_compile(mem, "\\[(\\d\\d:\\d+:\\d\\d)\\] (\\w+): (.+)")!;
    defer reg.free();
    
    String[] logs = {
        "[10:30:45] INFO: Server started",
        "[10:31:12] ERROR: Connection failed",
        "[10:32:00] WARNING: High memory usage"
    };
    
    foreach (log : logs) {
        int result = reg.match(log)!;
        if (result >= 0) {
            RegMatch time = reg.group(1)!;
            RegMatch level = reg.group(2)!;
            RegMatch message = reg.group(3)!;
            
            io::printfn("[%s] %s: %s", time.s, level.s, message.s);
        }
    }
}

fn void? example_html_tags()
{
    io::printn("\n=== 13. HTML Tag Removal Example ===");
    
    String html = "<p>Hello <strong>World</strong>!</p>";
    String pattern = "<[^>]+>";
    String replacement = "";
    
    String result = regex::reg_replace(mem, pattern, html, replacement)!;
    defer result.free(mem);
    
    io::printfn("Original HTML: %s", html);
    io::printfn("Text only: %s", result);
}

fn void? example_csv_parsing()
{
    io::printn("\n=== 14. CSV Parsing Example ===");
    
    String csv_line = "John,Doe,30,New York";
    String pattern = ",";
    
    List{String} fields = regex::reg_split(mem, pattern, csv_line)!;
    defer fields.free();
    
    io::printfn("CSV: %s", csv_line);
    io::printn("Fields:");
    io::printfn("  First name: %s", fields[0]);
    io::printfn("  Last name: %s", fields[1]);
    io::printfn("  Age: %s", fields[2]);
    io::printfn("  City: %s", fields[3]);
}

fn void? example_extract_numbers()
{
    io::printn("\n=== 15. Number Extraction and Sum Example ===");
    
    RegEx* reg = regex::new_compile(mem, "\\d+")!;
    defer reg.free();
    
    String text = "Apples: 5, Bananas: 10, Oranges: 3";
    
    List{int[2]} matches = reg.find_all(text);
    defer matches.free();
    
    io::printfn("Text: %s", text);
    
    int total = 0;
    foreach (pos : matches) {
        String num_str = text[pos[0]:pos[1]];
        // Simple string to int conversion in C3
        int num = 0;
        foreach (c : num_str) {
            num = num * 10 + (c - '0');
        }
        total += num;
        io::printfn("  Extracted: %s (%d)", num_str, num);
    }
    
    io::printfn("Total count: %d", total);
}

fn void? example_password_validation()
{
    io::printn("\n=== 16. Password Validation Example ===");
    
    // Password must contain at least one digit
    RegEx* has_digit = regex::new_compile(mem, "\\d")!;
    defer has_digit.free();
    
    // Password must contain at least one letter
    RegEx* has_letter = regex::new_compile(mem, "[a-zA-Z]")!;
    defer has_letter.free();
    
    String[] passwords = {
        "password123",
        "12345678",
        "SecurePass",
        "P@ssw0rd"
    };
    
    io::printn("Password validation:");
    foreach (pwd : passwords) {
        bool digit = has_digit.match(pwd)! >= 0;
        bool letter = has_letter.match(pwd)! >= 0;
        bool valid = digit && letter && pwd.len >= 8;
        
        io::printfn("  '%s': %s (len:%d, digit:%s, letter:%s)", 
                   pwd, valid ? "✓ Valid" : "✗ Invalid",
                   pwd.len, digit ? "✓" : "✗", letter ? "✓" : "✗");
    }
}

fn void? example_date_extraction()
{
    io::printn("\n=== 17. Date Extraction Example ===");
    
    // Match dates in YYYY-MM-DD format
    // \d{4} is not supported
    RegEx* reg = regex::new_compile(mem, "(\\d\\d\\d\\d)-(\\d\\d)-(\\d\\d)")!;
    defer reg.free();
    
    String text = "Meeting on 2024-03-15 and deadline 2024-12-31";
    
    List{int[2]} matches = reg.find_all(text);
    defer matches.free();
    
    io::printfn("Text: %s", text);
    io::printfn("Dates found:");
    
    foreach (i, pos : matches) {
        String date = text[pos[0]:pos[1]];
        
        // Re-match to get groups
        reg.match(date)!;
        RegMatch year = reg.group(1)!;
        RegMatch month = reg.group(2)!;
        RegMatch day = reg.group(3)!;
        
        io::printfn("  %d. %s → Year: %s, Month: %s, Day: %s", 
                   i+1, date, year.s, month.s, day.s);
    }
}

fn void? example_ip_address()
{
    io::printn("\n=== 18. IP Address Validation ===");
    
    // Simple IP address pattern (not perfect but demonstrates concept)
    RegEx* reg = regex::new_compile(mem, "^\\d+\\.\\d+\\.\\d+\\.\\d+$")!;
    defer reg.free();
    
    String[] ips = {
        "192.168.1.1",
        "10.0.0.1",
        "256.1.1.1",
        "192.168.1",
        "192.168.1.1.1"
    };
    
    io::printn("IP address validation:");
    foreach (ip : ips) {
        int result = reg.match(ip)!;
        io::printfn("  '%s': %s", ip, 
                   result >= 0 ? "✓ Valid format" : "✗ Invalid format");
    }
}

fn void? example_word_count()
{
    io::printn("\n=== 19. Word Count Example ===");
    
    String text = "The quick brown fox jumps over the lazy dog";
    String pattern = "\\w+";
    
    RegEx* reg = regex::new_compile(mem, pattern)!;
    defer reg.free();
    
    List{int[2]} matches = reg.find_all(text);
    defer matches.free();
    
    io::printfn("Text: %s", text);
    io::printfn("Word count: %d", matches.len());
    io::printn("Words:");
    
    foreach (i, pos : matches) {
        String word = text[pos[0]:pos[1]];
        io::printfn("  %d. '%s'", i+1, word);
    }
}

fn void? example_normalize_whitespace()
{
    io::printn("\n=== 20. Normalize Whitespace Example ===");
    
    String text = "Too    many     spaces   here";
    String pattern = " +";
    String replacement = " ";
    
    String result = regex::reg_replace(mem, pattern, text, replacement)!;
    defer result.free(mem);
    
    io::printfn("Original: '%s'", text);
    io::printfn("Normalized: '%s'", result);
}

fn void main()
{
    io::printn("╔════════════════════════════════════════╗");
    io::printn("║   C3 RegEx Library Usage Examples     ║");
    io::printn("╚════════════════════════════════════════╝");
    
    // Run all examples
    example_basic_match()!!;
    example_regex_object()!!;
    example_groups()!!;
    example_find_all()!!;
    example_replace()!!;
    example_replace_words()!!;
    example_split()!!;
    example_split_delimiters()!!;
    example_ignore_case()!!;
    example_validation()!!;
    example_url_parsing()!!;
    example_log_parsing()!!;
    example_html_tags()!!;
    example_csv_parsing()!!;
    example_extract_numbers()!!;
    example_password_validation()!!;
    example_date_extraction()!!;
    example_ip_address()!!;
    example_word_count()!!;
    example_normalize_whitespace()!!;
    
    io::printn("\nAll examples completed successfully!");
}
