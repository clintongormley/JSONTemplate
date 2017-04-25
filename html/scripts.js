var output, template, params, inputs, docs;
function setup() {
  output = $('#output');
  template = $('#template');
  params = $('#params');
  inputs = $('#params,#template');
  docs = $('#docs');
  converter = new showdown.Converter();

  autosize($('textarea'));
  inputs.keyup(check);
  check();
  render_docs();
}

function check() {
  var val = '{' + params.val() + '}';
  try {
    var json = JSON.parse(val);
    clear_error(params);
  } catch (e) {
    var msg = e.toString();
    var res = msg.match(/at position (\d+)/);
    if (res) {
      msg = msg.replace(/at position \d+/, '');
      val = val.substr(0, res[1]) + ' \u2B05 ' + val.substr(res[1]);
    }
    output.text(msg + "\n" + val);
    set_error(params);
    return;
  }

  $.ajax({
    url : '/render',
    data : $.param(inputs)
  }).done(function(data) {
    output.text('{ "query": ' + data + ' }');
    clear_error(template);
  }).fail(function(data) {
    output.text(data.responseText);
    set_error(template);
  });

}

function set_error(el) {
  if (!el.hasClass('error')) {
    el.addClass('error');
    output.addClass('error');
  }
}

function clear_error(el) {
  el.removeClass('error');
  output.removeClass('error');
}

function render_docs(e, num) {
  if (e) {
    e.preventDefault();
  }
  var page;
  if (num === undefined) {
    page = '# JSON Template' + "\n\n";
    for (var i = 0; i < Docs.length; i++) {
      page += "* <a href=\"#\" onclick=\"render_docs(event,"
        + i
        + ")\">"
        + Docs[i].header
        + "</a>\n";
    }
  } else {
    page = '# '
      + Docs[num].header
      + "\n\n"
      + Docs[num].content.join("\n")
      + "\n\n<hr>";
    if (num > 0) {
      page = page
        + "<a href=\"#\" onclick=\"render_docs(event,"
        + (num - 1)
        + ");\">"
        + "&#11013;"
        + "</a> ";
    }
    page = page + " <a href=\"#\" onclick=\"render_docs(event);\">Home</a> ";
    if (num < Docs.length - 1) {
      page = page
        + " <a href=\"#\" onclick=\"render_docs(event,"
        + (num + 1)
        + ");\">"
        + " &#10145;"
        + "</a> ";
    }
  }

  page = page.replace(
    /#(\w+):([^#]+)#/g,
    "<a href=\"#\" onclick=\"example(event," + num + ",'$1')\">$2</a>");
  docs.html(converter.makeHtml(page));

}

function example(e, num, which) {
  if (e) {
    e.preventDefault();
  }
  var example = Docs[num].examples[which];
  params.val(example.params);
  template.val(example.template);
  autosize.update($('textarea'));
  check();
}

var Docs = [

  {
    header : "Intro to JSON Template",
    content : [
      "JSON Template is a Mustache-inspired JSON-friendly templating language. "
        + "Unlike Mustache, where the whole string is a template, JSON Template is normal JSON, "
        + "but any JSON string can be a template.",
      "",
      "JSON Template can replace the string template with another string, ",
      "but it can also return other JSON elements like "
        + "`null`, `true`, `false`, numbers, arrays and objects.",
      "",
      "For instance:",
      "* **Strings:** as #strvar:variable# or #strinline:inline#",
      "* **Numbers:** as #numvar:variable# or #numinline:inline#",
      "* **Booleans:** as #boolvar:variable# or #boolinline:inline#",
      "* **Null:** as #nullvar:variable# or #nullinline:inline#",
      "* **Arrays:** as #arrvar:variable# or #arrinline:inline#",
      "* **Objects:** as #objvar:variable# or #objinline:inline# using the `json` function",
      "",
      "### Dot notation",
      "",
      "Inner objects and array items can be accessed using #dots:dot notation#."
    ],
    examples : {
      nullvar : {
        params : '"foo": null',
        template : '<< foo >>'
      },
      nullinline : {
        params : "",
        template : "<< null >>"
      },
      boolvar : {
        params : '"foo": true',
        template : '<< foo >>'
      },
      boolinline : {
        params : "",
        template : "<< false >>"
      },
      numvar : {
        params : '"foo": 5',
        template : '<< foo >>'
      },
      numinline : {
        params : "",
        template : "<< 5.2 >>"
      },
      strvar : {
        params : '"foo": "bar"',
        template : '<< foo >>'
      },
      strinline : {
        params : "",
        template : "<< 'bar' >>"
      },
      arrvar : {
        params : '"foo": ["one", "two", "three\\n" ]',
        template : '<< foo >>'
      },
      arrinline : {
        params : "",
        template : "<< 'one' \"two\" \"three\\n\" >>"
      },
      objvar : {
        params : '"user": {\n  "name": "John",\n  "age": 30 \n}',
        template : '<< user >>'
      },
      objinline : {
        params : '',
        template : '<< \'{ "foo": "bar" }\' | json >>'
      },
      dots : {
        params : '"users": [\n  { "name": "John",  "age": 30 },\n  { "name": "Alice", "age": 28 }\n]',
        template : '<< users.1.name >>'
      }
    }
  },
  {
    header : "Multiple Value Templates",
    content : [
      "If a template outputs more than one value or variable, the result is returned ",
      "#array:as a JSON array#.",
      "",
      "Similarly, an #var:array from a variable# is also returned as a JSON array.",
      "",
      "However, combining values with an array from a variable will #keep:keep the array# as it is",
      "unless you explicitly #flatten:flatten it# with the `flatten` pipe function.",
      "",
      "## Values outside `<<` `>>`",
      "If a template has any values outside the `<<` and `>>` delimiters, then that content ",
      "is rendered #exact:exactly as written# and concatenated with the template output.",
      "",
      "If the template outputs multiple values, they will #concat:all be concatenated#, "
        + "with arrays, objects, `null` values and booleans #concatjson:rendered as such#."
    ],
    examples : {
      array : {
        params : '"foo": "bar"',
        template : "<< foo 'baz' 5 >>"
      },
      "var" : {
        params : '"foo": [ "bar", "baz" ]',
        template : "<< foo >>"
      },
      "keep" : {
        params : '"foo": [ "bar", "baz" ]',
        template : "<< foo 'xyz'>>"
      },
      "flatten" : {
        params : '"foo": [ "bar", "baz" ]',
        template : "<< foo | flatten 'xyz'>>"
      },
      "exact" : {
        params : '"foo": "bar"',
        template : "ABC<< foo >>XYZ"
      },
      "concat" : {
        params : '"foo": "one",\n"bar": "two"',
        template : 'ABC<< foo bar >>XYZ'
      },
      "concatjson" : {
        params : '"foo": "one",\n"bar": [ "two" ]',
        template : 'ABC<< foo bar baz >>XYZ'
      }
    }
  },
  {
    header : "Pipe Functions",
    content : [
      "Any value or variable may be piped (`|`) through one or more functions:",
      "",
      "* #html:`html`# - HTML escapes a string",
      "* #json:`json`# - parses a JSON string",
      "* #lower:`lower`# - lowercases a string",
      "* #quote:`quote`# - adds double quotes around a string",
      "* #string:`string`# - renders JSON as a string",
      "* #upper:`upper`# - uppercases a string",
      "* #uri:`uri`# - URI escapes a string",
      "* or a #combo:combination# of multiple functions",
      "",
      "Pipe functions are only applied to the value #left:directly to their left#, ",
      "but you can #multi:apply functions to multiple values# by using `(` and `)` to create a group.",
      "",
      "While the above functions are applied to each element of an array, these functions ",
      "work on the whole array:",
      "",
      "* #array:`array`# - converts a group or value into an array",
      "* #flatten:`flatten`# - flattens an array",
      "* #join:`join`# - concatenates the elements of an array into a string",

    ],
    examples : {
      html : {
        params : '',
        template : "<< 'a < b' | html >>"
      },
      json : {
        params : '',
        template : "<< '{ \"foo\": \"bar\" }' | json >>"
      },
      string : {
        params : '"user": { "name": "John" }',
        template : "<< user | string>>"
      },
      lower : {
        params : '',
        template : "<< 'John' | lower >>"
      },
      quote : {
        params : '',
        template : "<< 'John Smith' | quote >>"
      },
      upper : {
        params : '',
        template : "<< 'John' | upper >>"
      },
      uri : {
        params : '',
        template : "<< 'a+b=5' | uri >>"
      },
      combo : {
        params : '',
        template : "<< 'John Smith' | upper | uri >>"
      },
      left : {
        params : '',
        template : "<<\n  'John' | lower\n  'Wilbur'\n  'Smith' | upper \n>>"
      },
      multi : {
        params : '',
        template : "<<\n  (\n    ('John' 'Wilbur') | quote\n    'Smith'\n  ) | upper\n>>"
      },
      array : {
        params : '',
        template : "<< 'one' ('two' 'three') ('four' 'five') | array >>"
      },
      flatten : {
        params : '"foo": [ "one", "two" ]',
        template : "<< foo foo | flatten 'three' >>"
      },
      join : {
        params : '',
        template : "<< (('one' 'two') | join 'three')|join(' - ') >>"
      }
    }
  },
  {
    header : "Concat Operator",
    content : [
      "The `+` is a simple concatenation operator for joining together ",
      "#str:two or more adjacent strings#. ",
      "",
      "If either the left or the right hand argument is a multi-value list, then the `+` ",
      "operator #merge:merges the two sides# instead. A single-value list functions "
        + "#single:like a string#."

    ],
    examples : {
      str : {
        params : '"foo": "=="',
        template : "<< foo + 'baz' + foo >>"
      },
      merge : {
        params : '"foo": "=="',
        template : "<< foo + ('bar' 'baz') + foo>>"
      },
      single : {
        params : '"foo": "=="',
        template : "<< foo + ('bar' 'baz') | join + foo>>"
      }
    }
  },
  {
    header : "Sections",
    content : [
      "Sections (like Mustache sections) render their contents one or more times, ",
      "based on the value of the specified variable.",
      "",
      "The syntax for a section is `varname< ... >`.",
      "",
      "If `varname` is an array then the section is treated as a `for` loop: ",
      "the section contents are executed once for every item in the array.",
      "The special variable `_` is set to the #array:value of the current list item#. ",
      "An empty list will #empty:not be executed#.",
      "",
      "If `varname` is a scalar then the section is #scalar:treated as an `if` block:# ",
      "the section contents are executed once if `varname` is anything but ",
      "`null`, `false`, or an empty string.",
      "",
      "If `varname` is an object then it behaves just like a `scalar`. The only difference ",
      "is that variable names within the section refer to #keys:keys within the current map#. ",
      "This also applies for an #arrobj:array of objects#.",
      "",
      "## Negated Sections",
      "A section can be negated (ie `true` treated as `false`) using the `!` operator: ",
      "`!varname< ... >`. With a negated section, the section will only be executed if ",
      "`varname` is:",
      "",
      "* #negnull:`null`#",
      "* #negfalse:`false`#",
      "* an #negstr:empty string#",
      "* an #neglist:empty array#."
    ],
    examples : {
      array : {
        params : '"foo": [ "One", "Two", "Three" ]',
        template : '<< foo< _ | lower _ | upper > >>'
      },
      empty : {
        params : '"foo": []',
        template : '<<\n   "Shown"\n   foo<"Not shown"> \n>>'
      },
      scalar : {
        params : '"show_me": "1",\n"not_me":  ""',
        template : "<<\n   show_me<'Shown'>\n   not_me<'Not shown'>\n>>"
      },
      keys : {
        params : '"user": { "name": "John", "age": 30 }',
        template : "<< user< name 'is' age > | join(' ') >>"
      },
      arrobj : {
        params : '"users": [\n  { "name": "John", "age": 30 },\n  { "name": "Alice", "age": 26 }\n]',
        template : "<<\n    users< (name 'is' age) | join(' ') >\n    | join(', ')\n>>"
      },
      negnull : {
        params : '"foo": null, "bar": 1',
        template : "<<\n   !foo<'Shown'>\n   !bar<'Not shown'>\n>>"
      },
      negfalse : {
        params : '"foo": false, "bar": 1',
        template : "<<\n   !foo<'Shown'>\n   !bar<'Not shown'>\n>>"
      },
      negstr : {
        params : '"foo": "", "bar": " "',
        template : "<<\n   !foo<'Shown'>\n   !bar<'Not shown'>\n>>"
      },
      neglist : {
        params : '"foo": [], "bar": [""]',
        template : "<<\n   !foo<'Shown'>\n   !bar<'Not shown'>\n>>"
      }
    }
  }
];
