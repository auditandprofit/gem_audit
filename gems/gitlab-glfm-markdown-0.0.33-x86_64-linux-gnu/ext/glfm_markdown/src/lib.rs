use magnus::{define_module, function, prelude::*, Error, RHash, Symbol};

mod glfm;
use glfm::{render, RenderOptions};

/// Lookup symbol in provided `RHash`. Returns `false` if the key is not present
/// or value cannot be converted to a boolean.
fn get_bool_opt(arg: &str, options: RHash) -> bool {
    options.lookup(Symbol::new(arg)).unwrap_or_default()
}

fn get_string_opt(arg: &str, options: RHash) -> Option<String> {
    options.lookup(Symbol::new(arg)).ok()
}

pub fn render_to_html_rs(text: String, options: RHash) -> String {
    let render_options = RenderOptions {
        alerts: get_bool_opt("alerts", options),
        autolink: get_bool_opt("autolink", options),
        // default_info_string: get_string_opt("default_info_string", options),
        description_lists: get_bool_opt("description_lists", options),
        escape: get_bool_opt("escape", options),
        escaped_char_spans: get_bool_opt("escaped_char_spans", options),
        figure_with_caption: get_bool_opt("figure_with_caption", options),
        footnotes: get_bool_opt("footnotes", options),
        // front_matter_delimiter: get_string_opt("front_matter_delimiter", options),
        full_info_string: get_bool_opt("full_info_string", options),
        gemojis: get_bool_opt("gemojis", options),
        gfm_quirks: get_bool_opt("gfm_quirks", options),
        github_pre_lang: get_bool_opt("github_pre_lang", options),
        greentext: get_bool_opt("greentext", options),
        hardbreaks: get_bool_opt("hardbreaks", options),
        header_ids: get_string_opt("header_ids", options),
        ignore_empty_links: get_bool_opt("ignore_empty_links", options),
        ignore_setext: get_bool_opt("ignore_setext", options),
        inapplicable_tasks: get_bool_opt("inapplicable_tasks", options),
        math_code: get_bool_opt("math_code", options),
        math_dollars: get_bool_opt("math_dollars", options),
        multiline_block_quotes: get_bool_opt("multiline_block_quotes", options),
        relaxed_autolinks: get_bool_opt("relaxed_autolinks", options),
        relaxed_tasklist_character: get_bool_opt("relaxed_tasklist_character", options),
        sourcepos: get_bool_opt("sourcepos", options),
        smart: get_bool_opt("smart", options),
        spoiler: get_bool_opt("spoiler", options),
        strikethrough: get_bool_opt("strikethrough", options),
        subscript: get_bool_opt("subscript", options),
        superscript: get_bool_opt("superscript", options),
        // syntax_highlighting: get_string_opt("syntax_highlighting", options),
        table: get_bool_opt("table", options),
        tagfilter: get_bool_opt("tagfilter", options),
        tasklist: get_bool_opt("tasklist", options),
        tasklist_classes: get_bool_opt("tasklist_classes", options),
        underline: get_bool_opt("underline", options),
        unsafe_: get_bool_opt("unsafe", options),
        wikilinks_title_after_pipe: get_bool_opt("wikilinks_title_after_pipe", options),
        wikilinks_title_before_pipe: get_bool_opt("wikilinks_title_before_pipe", options),

        default_html: get_bool_opt("default_html", options),
        placeholder_detection: get_bool_opt("placeholder_detection", options),
        debug: get_bool_opt("debug", options),
    };

    render(text, render_options)
}

#[magnus::init]
fn init() -> Result<(), Error> {
    let module = define_module("GLFMMarkdown")?;

    module.define_singleton_method("render_to_html_rs", function!(render_to_html_rs, 2))?;

    Ok(())
}
