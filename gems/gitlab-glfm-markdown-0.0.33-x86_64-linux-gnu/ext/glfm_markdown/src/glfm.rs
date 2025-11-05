use comrak::html::{ChildRendering, Context};
use comrak::nodes::{AstNode, ListType, NodeValue};
use comrak::{create_formatter, html, parse_document, Arena, Plugins};
use lazy_static::lazy_static;
use regex::Regex;
use std::io;
use std::io::{BufWriter, Write};

lazy_static! {
    static ref PLACEHOLDER_REGEX: Regex = Regex::new(r"%(\{|%7B)(\w{1,30})(}|%7D)").unwrap();
}

#[derive(Debug, Clone)]
pub struct RenderOptions {
    pub alerts: bool,
    pub autolink: bool,
    // pub default_info_string: String,
    pub description_lists: bool,
    pub escape: bool,
    pub escaped_char_spans: bool,
    pub figure_with_caption: bool,
    pub footnotes: bool,
    // pub front_matter_delimiter: String,
    pub full_info_string: bool,
    pub gemojis: bool,
    pub gfm_quirks: bool,
    pub github_pre_lang: bool,
    pub greentext: bool,
    pub hardbreaks: bool,
    pub header_ids: Option<String>,
    pub ignore_empty_links: bool,
    pub ignore_setext: bool,
    pub math_code: bool,
    pub math_dollars: bool,
    pub multiline_block_quotes: bool,
    pub relaxed_autolinks: bool,
    pub relaxed_tasklist_character: bool,
    pub sourcepos: bool,
    pub smart: bool,
    pub spoiler: bool,
    pub strikethrough: bool,
    pub subscript: bool,
    pub superscript: bool,
    // pub syntax_highlighting: String,
    pub table: bool,
    pub tagfilter: bool,
    pub tasklist: bool,
    pub tasklist_classes: bool,
    pub underline: bool,
    pub unsafe_: bool,
    pub wikilinks_title_after_pipe: bool,
    pub wikilinks_title_before_pipe: bool,

    /// GLFM specific options

    /// Only use default comrak HTML formatting
    pub default_html: bool,

    /// Detect inapplicable tasks (`- [~]`)
    pub inapplicable_tasks: bool,

    /// Detect and mark potential placeholder variables, which
    /// have the format `%{PLACEHOLDER}`
    pub placeholder_detection: bool,

    pub debug: bool,
}

pub struct RenderUserData {
    pub default_html: bool,
    pub inapplicable_tasks: bool,
    pub placeholder_detection: bool,
    pub debug: bool,
}

impl From<&RenderOptions> for RenderUserData {
    fn from(options: &RenderOptions) -> Self {
        RenderUserData {
            default_html: options.default_html,
            inapplicable_tasks: options.inapplicable_tasks,
            placeholder_detection: options.placeholder_detection,
            debug: options.debug,
        }
    }
}

impl From<&RenderOptions> for comrak::Options<'_> {
    fn from(options: &RenderOptions) -> Self {
        let mut comrak_options = comrak::Options::default();

        comrak_options.extension.alerts = options.alerts;
        comrak_options.extension.autolink = options.autolink;
        comrak_options.extension.description_lists = options.description_lists;
        comrak_options.extension.footnotes = options.footnotes;
        // comrak_options.extension.front_matter_delimiter = options.front_matter_delimiter;
        comrak_options.extension.greentext = options.greentext;
        comrak_options.extension.header_ids = options.header_ids.clone();
        comrak_options.extension.math_code = options.math_code;
        comrak_options.extension.math_dollars = options.math_dollars;
        comrak_options.extension.multiline_block_quotes = options.multiline_block_quotes;
        comrak_options.extension.shortcodes = options.gemojis;
        comrak_options.extension.spoiler = options.spoiler;
        comrak_options.extension.strikethrough = options.strikethrough;
        comrak_options.extension.subscript = options.subscript;
        comrak_options.extension.superscript = options.superscript;
        comrak_options.extension.table = options.table;
        comrak_options.extension.tagfilter = options.tagfilter;
        comrak_options.extension.tasklist = options.tasklist;
        comrak_options.extension.underline = options.underline;
        comrak_options.extension.wikilinks_title_after_pipe = options.wikilinks_title_after_pipe;
        comrak_options.extension.wikilinks_title_before_pipe = options.wikilinks_title_before_pipe;

        comrak_options.render.escape = options.escape;
        comrak_options.render.escaped_char_spans = options.escaped_char_spans;
        comrak_options.render.figure_with_caption = options.figure_with_caption;
        comrak_options.render.full_info_string = options.full_info_string;
        comrak_options.render.gfm_quirks = options.gfm_quirks;
        comrak_options.render.github_pre_lang = options.github_pre_lang;
        comrak_options.render.hardbreaks = options.hardbreaks;
        comrak_options.render.ignore_empty_links = options.ignore_empty_links;
        comrak_options.render.ignore_setext = options.ignore_setext;
        comrak_options.render.sourcepos = options.sourcepos;
        comrak_options.render.tasklist_classes = options.tasklist_classes;
        // comrak_options.render.syntax_highlighting = options.syntax_highlighting;

        comrak_options.render.unsafe_ = options.unsafe_;

        // comrak_options.parse.default_info_string = options.default_info_string;
        comrak_options.parse.relaxed_autolinks = options.relaxed_autolinks;
        comrak_options.parse.relaxed_tasklist_matching = options.relaxed_tasklist_character;
        comrak_options.parse.smart = options.smart;

        comrak_options
    }
}

pub fn render(text: String, options: RenderOptions) -> String {
    render_with_plugins(text, options, &comrak::Plugins::default())
}

fn render_with_plugins(text: String, render_options: RenderOptions, plugins: &Plugins) -> String {
    let user_data = RenderUserData::from(&render_options);
    let options = comrak::Options::from(&render_options);

    if user_data.default_html {
        return comrak::markdown_to_html_with_plugins(&text, &options, plugins);
    }

    let arena = Arena::new();
    let root = parse_document(&arena, &text, &options);
    let mut bw = BufWriter::new(Vec::new());

    CustomFormatter::format_document_with_plugins(root, &options, &mut bw, plugins, user_data)
        .unwrap();
    String::from_utf8(bw.into_inner().unwrap()).unwrap()
}

// The important thing to remember is that this overrides the default behavior of the
// specified nodes. If we do override a node, then it's our responsibility to ensure that
// any changes in the `comrak` code for those nodes is backported to here, such as when
// `figcaption` support was added.
// One idea to limit that would be having the ability to specify attributes that would
// be inserted when a node is rendered. That would allow us to (in many cases) just
// inject the changes we need. Such a feature would need to be added to `comrak`.
create_formatter!(CustomFormatter<RenderUserData>, {
    NodeValue::Text(_) => |context, node, entering| {
        return render_text(context, node, entering);
    },
    NodeValue::Link(_) => |context, node, entering| {
        return render_link(context, node, entering);
    },
    NodeValue::Image(_) => |context, node, entering| {
        return render_image(context, node, entering);
    },
    NodeValue::List(_) => |context, node, entering| {
        return render_list(context, node, entering);
    },
    NodeValue::TaskItem(_) => |context, node, entering| {
        return render_task_item(context, node, entering);
    }
});

fn render_image<'a>(
    context: &mut Context<RenderUserData>,
    node: &'a AstNode<'a>,
    entering: bool,
) -> io::Result<ChildRendering> {
    let NodeValue::Image(ref nl) = node.data.borrow().value else {
        panic!("Attempt to render invalid node as image")
    };

    if !(context.user.placeholder_detection && PLACEHOLDER_REGEX.is_match(nl.url.as_str())) {
        return html::format_node_default(context, node, entering);
    }

    if entering {
        if context.options.render.figure_with_caption {
            context.write_all(b"<figure>")?;
        }
        context.write_all(b"<img")?;
        html::render_sourcepos(context, node)?;
        context.write_all(b" src=\"")?;
        let url = nl.url.as_bytes();
        if context.options.render.unsafe_ || !html::dangerous_url(url) {
            if let Some(rewriter) = &context.options.extension.image_url_rewriter {
                context.escape_href(rewriter.to_html(&nl.url).as_bytes())?;
            } else {
                context.escape_href(url)?;
            }
        }

        context.write_all(b"\"")?;

        if PLACEHOLDER_REGEX.is_match(nl.url.as_str()) {
            context.write_all(b" data-placeholder")?;
        }

        context.write_all(b" alt=\"")?;

        return Ok(ChildRendering::Plain);
    } else {
        if !nl.title.is_empty() {
            context.write_all(b"\" title=\"")?;
            context.escape(nl.title.as_bytes())?;
        }
        context.write_all(b"\" />")?;
        if context.options.render.figure_with_caption {
            if !nl.title.is_empty() {
                context.write_all(b"<figcaption>")?;
                context.escape(nl.title.as_bytes())?;
                context.write_all(b"</figcaption>")?;
            }
            context.write_all(b"</figure>")?;
        };
    }

    Ok(ChildRendering::HTML)
}

fn render_link<'a>(
    context: &mut Context<RenderUserData>,
    node: &'a AstNode<'a>,
    entering: bool,
) -> io::Result<ChildRendering> {
    let NodeValue::Link(ref nl) = node.data.borrow().value else {
        panic!("Attempt to render invalid node as link")
    };

    if !(context.user.placeholder_detection && PLACEHOLDER_REGEX.is_match(nl.url.as_str())) {
        return html::format_node_default(context, node, entering);
    }

    let parent_node = node.parent();

    if !context.options.parse.relaxed_autolinks
        || (parent_node.is_none()
            || !matches!(
                parent_node.unwrap().data.borrow().value,
                NodeValue::Link(..)
            ))
    {
        if entering {
            context.write_all(b"<a")?;
            html::render_sourcepos(context, node)?;
            context.write_all(b" href=\"")?;
            let url = nl.url.as_bytes();
            if context.options.render.unsafe_ || !html::dangerous_url(url) {
                if let Some(rewriter) = &context.options.extension.link_url_rewriter {
                    context.escape_href(rewriter.to_html(&nl.url).as_bytes())?;
                } else {
                    context.escape_href(url)?;
                }
            }
            context.write_all(b"\"")?;

            if !nl.title.is_empty() {
                context.write_all(b" title=\"")?;
                context.escape(nl.title.as_bytes())?;
            }

            if PLACEHOLDER_REGEX.is_match(nl.url.as_str()) {
                context.write_all(b" data-placeholder")?;
            }

            context.write_all(b">")?;
        } else {
            context.write_all(b"</a>")?;
        }
    }

    Ok(ChildRendering::HTML)
}

// Overridden to use class `task-list` instead of `contains-task-list`
// to align with GitLab class usage
fn render_list<'a>(
    context: &mut Context<RenderUserData>,
    node: &'a AstNode<'a>,
    entering: bool,
) -> io::Result<ChildRendering> {
    if !entering || !context.options.render.tasklist_classes {
        return html::format_node_default(context, node, entering);
    }

    let NodeValue::List(ref nl) = node.data.borrow().value else {
        panic!("Attempt to render invalid node as list")
    };

    context.cr()?;
    match nl.list_type {
        ListType::Bullet => {
            context.write_all(b"<ul")?;
            if nl.is_task_list {
                context.write_all(b" class=\"task-list\"")?;
            }
            html::render_sourcepos(context, node)?;
            context.write_all(b">\n")?;
        }
        ListType::Ordered => {
            context.write_all(b"<ol")?;
            if nl.is_task_list {
                context.write_all(b" class=\"task-list\"")?;
            }
            html::render_sourcepos(context, node)?;
            if nl.start == 1 {
                context.write_all(b">\n")?;
            } else {
                writeln!(context, " start=\"{}\">", nl.start)?;
            }
        }
    }

    Ok(ChildRendering::HTML)
}

// Overridden to detect inapplicable task list items
fn render_task_item<'a>(
    context: &mut Context<RenderUserData>,
    node: &'a AstNode<'a>,
    entering: bool,
) -> io::Result<ChildRendering> {
    if !context.user.inapplicable_tasks {
        return html::format_node_default(context, node, entering);
    }

    let NodeValue::TaskItem(symbol) = node.data.borrow().value else {
        panic!("Attempt to render invalid node as task item")
    };

    if symbol.is_none() || matches!(symbol, Some('x' | 'X')) {
        return html::format_node_default(context, node, entering);
    }

    if entering {
        // Handle an inapplicable task symbol.
        if matches!(symbol, Some('~')) {
            context.cr()?;
            context.write_all(b"<li")?;
            context.write_all(b" class=\"inapplicable")?;

            if context.options.render.tasklist_classes {
                context.write_all(b" task-list-item")?;
            }
            context.write_all(b"\"")?;

            html::render_sourcepos(context, node)?;
            context.write_all(b">")?;
            context.write_all(b"<input type=\"checkbox\"")?;

            if context.options.render.tasklist_classes {
                context.write_all(b" class=\"task-list-item-checkbox\"")?;
            }

            context.write_all(b" data-inapplicable disabled=\"\"> ")?;
        } else {
            // Don't allow unsupported symbols to render a checkbox
            context.cr()?;
            context.write_all(b"<li")?;

            if context.options.render.tasklist_classes {
                context.write_all(b" class=\"task-list-item\"")?;
            }

            html::render_sourcepos(context, node)?;
            context.write_all(b">")?;
            context.write_all(b"[")?;
            context.escape(symbol.unwrap().to_string().as_bytes())?;
            context.write_all(b"] ")?;
        }
    } else {
        context.write_all(b"</li>\n")?;
    }

    Ok(ChildRendering::HTML)
}
fn render_text<'a>(
    context: &mut Context<RenderUserData>,
    node: &'a AstNode<'a>,
    entering: bool,
) -> io::Result<ChildRendering> {
    let NodeValue::Text(ref literal) = node.data.borrow().value else {
        panic!("Attempt to render invalid node as text")
    };

    if !(context.user.placeholder_detection && PLACEHOLDER_REGEX.is_match(literal)) {
        return html::format_node_default(context, node, entering);
    }

    // Don't currently support placeholders in the text inside links or images.
    // If the text has an underscore in it, then the parser will not combine
    // the multiple text nodes in `comrak`'s `postprocess_text_nodes`, breaking up
    // the placeholder into multiple text nodes.
    // For example, `[%{a_b}](link)`.
    let parent = node.parent().unwrap();
    if matches!(
        parent.data.borrow().value,
        NodeValue::Link(_) | NodeValue::Image(_)
    ) {
        return html::format_node_default(context, node, entering);
    }

    if entering {
        let mut cursor: usize = 0;

        for mat in PLACEHOLDER_REGEX.find_iter(literal) {
            if mat.start() > cursor {
                context.escape(literal[cursor..mat.start()].as_bytes())?;
            }

            context.write_all(b"<span data-placeholder>")?;
            context.escape(literal[mat.start()..mat.end()].as_bytes())?;
            context.write_all(b"</span>")?;

            cursor = mat.end();
        }

        if cursor < literal.len() {
            context.escape(literal[cursor..literal.len()].as_bytes())?;
        }
    }

    Ok(ChildRendering::HTML)
}
