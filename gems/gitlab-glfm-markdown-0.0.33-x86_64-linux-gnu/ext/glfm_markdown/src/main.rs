mod glfm;
use glfm::{render, RenderOptions};
use std::io::Read;
use std::io::Write;

use clap::Parser;

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// CommonMark file(s) to parse; or standard input if none passed
    #[arg(value_name = "FILE")]
    file: Option<String>,

    /// Enable 'alerts' extension
    #[arg(long)]
    alerts: bool,

    /// Enable 'autolink' extension
    #[arg(long)]
    autolink: bool,

    /// Enable 'description-lists' extension
    #[arg(long)]
    description_lists: bool,

    /// Escape raw HTML instead of clobbering it
    #[arg(long)]
    escape: bool,

    /// Wrap escaped characters in a `<span>` to allow any post-processing to recognize them
    #[arg(long)]
    escaped_char_spans: bool,

    /// Render the image as a figure element with the title as its caption
    #[arg(long)]
    figure_with_caption: bool,

    /// Enable 'footnotes' extension
    #[arg(long)]
    footnotes: bool,

    /// Ignore front-matter that starts and ends with the given string
    // #[arg(long, value_name = "DELIMITER", allow_hyphen_values = true)]
    // front_matter_delimiter: Option<String>,

    /// Enable full info strings for code blocks
    #[arg(long)]
    full_info_string: bool,

    /// Translate gemojis into UTF-8 characters
    #[arg(long)]
    gemojis: bool,

    /// Enables GFM-style quirks in output HTML, such as not nesting <strong>
    /// tags, which otherwise breaks CommonMark compatibility.
    #[arg(long)]
    gfm_quirks: bool,

    /// Use GitHub-style <pre lang> for code blocks
    #[arg(long)]
    github_pre_lang: bool,

    /// Requires at least one space after a `>` character to generate a blockquote,
    /// and restarts blockquote nesting across unique lines of input
    #[arg(long)]
    greentext: bool,

    /// Treat newlines as hard line breaks
    #[arg(long)]
    hardbreaks: bool,

    /// Enable the 'header IDs` extension, with the given ID prefix
    #[arg(long, value_name = "PREFIX")]
    header_ids: Option<String>,

    /// Ignore empty links in input.
    #[arg(long)]
    ignore_empty_links: bool,

    /// Ignore setext headings in input.
    #[arg(long)]
    ignore_setext: bool,

    /// Enables `math code` extension, using math code syntax
    #[arg(long)]
    math_code: bool,

    /// Enables `math dollar` extension, using math dollar syntax
    #[arg(long)]
    math_dollars: bool,

    /// Enable 'multiline block quotes' extension
    #[arg(long)]
    multiline_block_quotes: bool,

    /// Write output to FILE instead of stdout
    #[arg(short, long, value_name = "FILE")]
    output: Option<String>,

    /// Enable relaxing of autolink parsing, allowing links to be recognized when in brackets
    #[arg(long)]
    relaxed_autolinks: bool,

    /// Enable relaxing which character is allowed in a tasklists
    #[arg(long)]
    relaxed_tasklist_character: bool,

    /// Include source mappings in HTML attributes
    #[arg(long)]
    sourcepos: bool,

    /// Use smart punctuation
    #[arg(long)]
    smart: bool,

    /// Enables spoilers using double vertical bars
    #[arg(long)]
    spoiler: bool,

    /// Enable 'strikethrough' extension
    #[arg(long)]
    strikethrough: bool,

    /// Enable 'subscript' extension
    #[arg(long)]
    subscript: bool,

    /// Enable 'superscript' extension
    #[arg(long)]
    superscript: bool,

    /// Syntax highlighting for codefence blocks. Choose a theme or 'none' for disabling.
    // #[arg(long, value_name = "THEME", default_value = "base16-ocean.dark")]
    // syntax_highlighting: String,

    /// Enable 'table' extension
    #[arg(long)]
    table: bool,

    /// Enable 'tagfilter' extension
    #[arg(long)]
    tagfilter: bool,

    /// Enable 'tasklist' extension
    #[arg(long)]
    tasklist: bool,

    /// Output classes on tasklist elements so that they can be styled with CSS
    #[arg(long)]
    tasklist_clases: bool,

    /// Enables underlines using double underscores
    #[arg(long)]
    underline: bool,

    /// Allow raw HTML and dangerous URLs
    #[arg(long = "unsafe")]
    unsafe_: bool,

    /// Enable 'wikilink_title_after_pipe' extension
    #[arg(long)]
    wikilinks_title_after_pipe: bool,

    /// Enable 'wikilink_title_before_pipe' extension
    #[arg(long)]
    wikilinks_title_before_pipe: bool,

    /// Only use default comrak HTML formatting
    #[arg(long)]
    default_html: bool,

    /// GLFM specific options

    /// Detect inapplicable tasks (`- [~]`)
    #[arg(long)]
    inapplicable_tasks: bool,

    /// Detect and marks potential placeholder variables, which
    /// have the format `%{PLACEHOLDER}`
    #[arg(long)]
    placeholder_detection: bool,

    /// Show debug information
    #[arg(long)]
    debug: bool,
}

fn main() {
    let mut s: Vec<u8> = Vec::with_capacity(2048);
    let cli = Args::parse();

    match cli.file {
        None => {
            std::io::stdin().read_to_end(&mut s).unwrap();
        }
        Some(fs) => {
            s = std::fs::read(fs).unwrap();
        }
    };

    let source = String::from_utf8_lossy(&s);
    let options = RenderOptions {
        alerts: cli.alerts,
        autolink: cli.autolink,
        // default_info_string:
        description_lists: cli.description_lists,
        escape: cli.escape,
        escaped_char_spans: cli.escaped_char_spans,
        figure_with_caption: cli.figure_with_caption,
        footnotes: cli.footnotes,
        // front_matter_delimiter:
        full_info_string: cli.full_info_string,
        gemojis: cli.gemojis,
        gfm_quirks: cli.gfm_quirks,
        github_pre_lang: cli.github_pre_lang,
        greentext: cli.greentext,
        hardbreaks: cli.hardbreaks,
        header_ids: cli.header_ids,
        ignore_empty_links: cli.ignore_empty_links,
        ignore_setext: cli.ignore_setext,
        inapplicable_tasks: cli.inapplicable_tasks,
        math_code: cli.math_code,
        math_dollars: cli.math_dollars,
        multiline_block_quotes: cli.multiline_block_quotes,
        relaxed_autolinks: cli.relaxed_autolinks,
        relaxed_tasklist_character: cli.relaxed_tasklist_character,
        sourcepos: cli.sourcepos,
        smart: cli.smart,
        spoiler: cli.spoiler,
        strikethrough: cli.strikethrough,
        subscript: cli.subscript,
        superscript: cli.superscript,
        // syntax_highlighting:
        table: cli.table,
        tagfilter: cli.tagfilter,
        tasklist: cli.tasklist,
        tasklist_classes: cli.tasklist_classes,
        underline: cli.underline,
        unsafe_: cli.unsafe_,
        wikilinks_title_after_pipe: cli.wikilinks_title_after_pipe,
        wikilinks_title_before_pipe: cli.wikilinks_title_before_pipe,

        default_html: cli.default_html,
        placeholder_detection: cli.placeholder_detection,
        debug: cli.debug,
    };

    let result = render(source.to_string(), options);

    if let Some(output_filename) = cli.output {
        std::fs::write(output_filename, &result).unwrap();
    } else {
        std::io::stdout().write_all(result.as_bytes()).unwrap();
    };
}
