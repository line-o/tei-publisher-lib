(:
 :
 :  Copyright (C) 2015 Wolfgang Meier
 :
 :  This program is free software: you can redistribute it and/or modify
 :  it under the terms of the GNU General Public License as published by
 :  the Free Software Foundation, either version 3 of the License, or
 :  (at your option) any later version.
 :
 :  This program is distributed in the hope that it will be useful,
 :  but WITHOUT ANY WARRANTY; without even the implied warranty of
 :  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 :  GNU General Public License for more details.
 :
 :  You should have received a copy of the GNU General Public License
 :  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 :)
xquery version "3.1";

(:~
 : Parses an ODD and generates an XQuery transformation module based on
 : the TEI Simple Processing Model.
 :
 : @author Wolfgang Meier
 :)
module namespace pm="http://www.tei-c.org/tei-simple/xquery/model";

import module namespace xqgen="http://www.tei-c.org/tei-simple/xquery/xqgen";

declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace pb="http://teipublisher.com/1.0";


declare variable $pm:ERR_TOO_MANY_MODELS := xs:QName("pm:too-many-models");
declare variable $pm:MULTIPLE_FUNCTIONS_FOUND := xs:QName("pm:multiple-functions");
declare variable $pm:NOT_FOUND := xs:QName("pm:not-found");

(:~
 : Parse the given ODD and generate an XQuery transformation module.
 :
 : @param $odd the root node of the ODD document
 : @param $modules an array of maps. Each map defines a module to be used for resolving
 : processing model functions. The first function whose name and parameters match the behaviour
 : will be used.
 : @param output the output method to use ("web" by default)
 :)
declare function pm:parse($odd as element(), $modules as array(*), $output as xs:string*) as map(*) {
    let $output := if (exists($output)) then $output else "web"
    let $oddPath := ($odd/@source/string(), document-uri(root($odd)))[1]
    let $name := replace($oddPath, "^.*?([^/\.]+)\.[^\.]+$", "$1")
    let $uri := "http://www.tei-c.org/pm/models/" || $name || "/" || $output[1]
    let $root := $odd/ancestor-or-self::tei:TEI
    let $specNS :=
        if ($root//tei:schemaSpec/@ns) then
            $root//tei:schemaSpec/@ns/string()
        else
            "http://www.tei-c.org/ns/1.0"
    let $prefixes := in-scope-prefixes($root)[not(. = ("", "xml", "xhtml", "css"))]
    let $namespaces := $prefixes ! namespace-uri-for-prefix(., $root)
    let $moduleDesc := pm:load-modules($modules)
    let $xqueryXML :=
        <xquery>
            <comment type="xqdoc">
                Transformation module generated from TEI ODD extensions for processing models.

                ODD: { $oddPath }
            </comment>
            <module prefix="model" uri="{$uri}">
                <default-element-namespace>
                { $specNS }
                </default-element-namespace>
                <declare-namespace prefix="xhtml" uri="http://www.w3.org/1999/xhtml"/>
                <!--
                    Should dynamically generate namespace declarations for all namespaces defined
                    on the root element of the odd. -->
                {
                    for-each-pair($prefixes, $namespaces, function($prefix, $ns) {
                        <declare-namespace prefix="{$prefix}" uri="{$ns}"/>
                    })
                }
                <import-module prefix="css" uri="http://www.tei-c.org/tei-simple/xquery/css"/>
                { pm:import-modules($modules) }
                { pm:declare-template-functions($odd) }
                <comment type="xqdoc">
                    Main entry point for the transformation.
                </comment>
                <function name="model:transform">
                    <param>$options as map(*)</param>
                    <param>$input as node()*</param>
                    <body>
let $config :=
    map:new(($options,
        map {{
            "output": [{ string-join(for $out in $output return '"' || $out || '"', ",")}],
            "odd": "{ $oddPath }",
            "apply": model:apply#2,
            "apply-children": model:apply-children#3
        }}
    ))
{ pm:init-modules($moduleDesc) }
return (
    { pm:prepare-modules($moduleDesc) }
    let $output := model:apply($config, $input)
    return
        { pm:finish-modules($moduleDesc) }
)</body>
                </function>
                <function name="model:apply">
                    <param>$config as map(*)</param>
                    <param>$input as node()*</param>
                    <body>
                        <let var="parameters">
                            <expr>if (exists($config?parameters)) then $config?parameters else map {{}}</expr>
                            <return>
                                <var>input</var>
                                <bang/>
                                <sequence>
                                    <item>
                                        <let var="node">
                                            <expr>.</expr>
                                            <return>
                                                <typeswitch op=".">
                                                    {
                                                        for $spec in $odd//tei:elementSpec[not(@ident=('text()', '*'))][.//tei:model]
                                                        let $case := pm:elementSpec($spec, $moduleDesc, $output)
                                                        return
                                                            if (exists($case)) then (
                                                                if ($spec/tei:desc) then
                                                                    <comment>{$spec/tei:desc/string()}</comment>
                                                                else
                                                                    (),
                                                                <case test="element({$spec/@ident})">
                                                                {$case}
                                                                </case>
                                                            ) else
                                                                (),
                                                        if ($output = "web") then
                                                            <case test="element(exist:match)">
                                                                <function-call name="{$modules?1?prefix}:match">
                                                                    <param>$config</param>
                                                                    <param>.</param>
                                                                    <param>.</param>
                                                                </function-call>
                                                            </case>
                                                        else
                                                            (),
                                                        let $defaultSpec := $odd//tei:elementSpec[@ident="*"]
                                                        return
                                                            if ($defaultSpec) then
                                                                <case test="element()">
                                                                {
                                                                    pm:process-models(
                                                                        "-element",
                                                                        pm:get-model-elements($defaultSpec, $output),
                                                                        $moduleDesc,
                                                                        $output
                                                                    )
                                                                }
                                                                </case>
                                                            else
                                                                <case test="element()">
                                                                    <if test="namespace-uri(.) = '{$specNS}'">
                                                                        <then>
                                                                            <function-call name="$config?apply">
                                                                                <param>$config</param>
                                                                                <param>./node()</param>
                                                                            </function-call>
                                                                        </then>
                                                                        <else>.</else>
                                                                    </if>
                                                                </case>,
                                                        let $defaultSpec := $odd//tei:elementSpec[@ident="text()"]
                                                        return
                                                            if ($defaultSpec) then
                                                                <case test="text() | xs:anyAtomicType">
                                                                {
                                                                    pm:process-models(
                                                                        "-text",
                                                                        pm:get-model-elements($defaultSpec, $output),
                                                                        $moduleDesc,
                                                                        $output
                                                                    )
                                                                }
                                                                </case>
                                                            else
                                                                <case test="text() | xs:anyAtomicType">
                                                                {
                                                                    let $charFn := pm:lookup($moduleDesc, "characters", 1)
                                                                    return
                                                                        if (exists($charFn)) then
                                                                            <function-call name="{$charFn?prefix}:characters">
                                                                                <param>.</param>
                                                                            </function-call>
                                                                        else
                                                                            <function-call name="{$modules?1?prefix}:escapeChars">
                                                                                <param>.</param>
                                                                            </function-call>
                                                                }
                                                                </case>
                                                    }
                                                    <default>
                                                        <function-call name="$config?apply">
                                                            <param>$config</param>
                                                            <param>./node()</param>
                                                        </function-call>
                                                    </default>
                                                </typeswitch>
                                            </return>
                                        </let>
                                    </item>
                                </sequence>
                            </return>
                        </let>
                    </body>
                </function>
                <function name="model:apply-children">
                    <param>$config as map(*)</param>
                    <param>$node as element()</param>
                    <param>$content as item()*</param>
                    <body>
$content ! (
    typeswitch(.)
        case element() return
            if (. is $node) then
                $config?apply($config, ./node())
            else
                $config?apply($config, .)
        default return
            {$modules?1?prefix}:escapeChars(.)
)</body>
            </function>
            </module>
        </xquery>
    return
        map {
            "uri": $uri,
            "code": xqgen:generate($xqueryXML, 0)
        }
};

declare function pm:load-modules($modules as array(*)) as array(*) {
    array:for-each($modules, function($module) {
        let $meta :=
            if ($module?at) then
                inspect:inspect-module(xs:anyURI($module?at))
            else
                inspect:inspect-module-uri(xs:anyURI($module?uri))
        return
            map:new(($module, map { "description": $meta }))
    })
};

declare %private function pm:import-modules($modules as array(*)) {
    array:for-each($modules, function($module) {
        <import-module prefix="{$module?prefix}" uri="{$module?uri}" at="{$module?at}"/>
    })
};

declare %private function pm:init-modules($modules as array(*)) {
    array:for-each($modules, function($module) {
        let $moduleDesc := $module?description
        for $fn in $moduleDesc/function[@name = $moduleDesc/@prefix || ":init"][count(argument) = 2]
        return
            "let $config := " || $module?prefix || ":init($config, $input)&#10;"
    })
};

declare %private function pm:prepare-modules($modules as array(*)) {
    array:for-each($modules, function($module) {
        let $moduleDesc := $module?description
        for $fn in $moduleDesc/function[@name = $moduleDesc/@prefix || ":prepare"][count(argument) = 2]
        return
            $module?prefix || ":prepare($config, $input),&#10;"
    })
};

declare %private function pm:finish-modules($modules as array(*)) {
    let $funcs :=
        array:flatten(
            array:for-each($modules, function($module) {
                let $moduleDesc := $module?description
                for $fn in $moduleDesc/function[@name = $moduleDesc/@prefix || ":finish"][count(argument) = 2]
                return
                    $module?prefix || ":finish"
            })
        )
    return
        fold-left($funcs, "$output", function($zero, $fn) {
            $fn || '($config, ' || $zero || ')'
        })
};


declare %private function pm:elementSpec($spec as element(tei:elementSpec), $modules as array(*), $output as xs:string+) {
    pm:process-models(
        $spec/@ident,
        pm:get-model-elements($spec, $output),
        $modules,
        $output
    )
};

declare %private function pm:process-models($ident as xs:string, $models as element()+, $modules as array(*),
    $output as xs:string+) {
    if ($models[@predicate]) then
        fold-right($models[@predicate], (), function($cond, $zero) {
            <if test="{$cond/@predicate}">
                <then>{pm:model-or-sequence($ident, $cond, $modules, $output)}</then>
                {
                    if ($zero) then
                        <else>{$zero}</else>
                    else
                        <else>
                        {
                            if ($models[not(@predicate)]) then
                                if (count($models[not(@predicate)]) > 1 and not($models/parent::tei:modelSequence)) then (
                                    <comment>More than one model without predicate found for ident {$ident}.
                                    Choosing first one.</comment>,
                                    pm:model-or-sequence($ident, $models[not(@predicate)][1], $modules, $output)
(:                                    error($pm:ERR_TOO_MANY_MODELS,:)
(:                                        "More than one model without predicate found " ||:)
(:                                        "outside modelSequence for ident '" || $ident || "'"):)
                                ) else
                                    pm:model-or-sequence($ident, $models[not(@predicate)], $modules, $output)
                            else
                                <function-call name="$config?apply">
                                    <param>$config</param>
                                    <param>./node()</param>
                                </function-call>
                        }
                        </else>
                }
            </if>
        })
    else if (count($models) > 1 and not($models/parent::tei:modelSequence)) then (
        <comment>More than one model without predicate found for ident {$ident}.
        Choosing first one.</comment>,
        pm:model-or-sequence($ident, $models[1], $modules, $output)
    ) else
        $models ! pm:model-or-sequence($ident, ., $modules, $output)
};

declare %private function pm:model-or-sequence($ident as xs:string, $models as element()+,
    $modules as array(*), $output as xs:string+) {
    for $model in $models
    return
        typeswitch($model)
            case element(tei:model) return
                pm:model($ident, $model, $modules, $output)
            case element(tei:modelSequence) return
                pm:modelSequence($ident, $model, $modules, $output)
            case element(tei:modelGrp) return
                pm:process-models($ident, $model/*, $modules, $output)
            default return
                ()
};

declare %private function pm:model($ident as xs:string, $model as element(tei:model), $modules as array(*), $output as xs:string+) {
    let $behaviour := $model/@behaviour
    let $task := normalize-space($model/@behaviour)
    let $nested := pm:get-model-elements($model, $output)
    let $content :=
        if ($nested) then
            pm:process-models($ident, $nested, $modules, $output)
        else
            "."
    let $params := $model/tei:param
    let $params := if (empty($params[@name="content"])) then ($params, <tei:param name="content" value="{$content}"/>) else $params
    let $fn := pm:lookup($modules, $task, count($params) + 3)
    return
        if (exists($fn)) then (
            if (count($fn?function) > 1) then
                <comment>More than one function found matching behaviour {$behaviour/string()}</comment>
            else
                (),
            let $signature := $fn?function[1]
            let $classes := pm:get-class($ident, $model)
            let $spec := $model/ancestor::tei:elementSpec[1]
            return
                try {
                    if ($model/tei:desc) then
                        <comment>{$model/tei:desc}</comment>
                    else
                        (),
                    pm:expand-template($model, $params),
                    <function-call name="{$fn?prefix}:{$task}">
                        {
                            if ($model/pb:template) then
                                <param>map:merge(($config, map:entry("template", true())))</param>
                            else
                                <param>$config</param>
                        }
                        <param>.</param>
                        <param>
                        {
                            if ($model/@useSourceRendition = "true") then
                                <function-call name="css:get-rendition">
                                    <param>.</param>
                                    <param>({string-join(for $class in $classes return $class, ", ")})</param>
                                </function-call>
                            else
                                "(" || string-join(for $class in $classes return $class, ", ") || ")"
                        }
                        </param>
                        {
                            pm:map-parameters($signature, $params, $ident, $modules, $output, exists($model/pb:template)),
                            pm:optional-parameters($signature, $params)
                        }
                    </function-call>
                } catch pm:not-found {
                    <comment>Failed to map function for behavior {$behaviour/string()}. {$err:description}</comment>,
                    <comment>{serialize($model)}</comment>,
                    "()"
                }
        ) else (
            <comment>No function found for behavior: {$behaviour/string()}</comment>,
            <function-call name="$config?apply">
                <param>$config</param>
                <param>./node()</param>
            </function-call>
        )
};

declare %private function pm:modelSequence($ident as xs:string, $seq as element(tei:modelSequence),
    $modules as array(*), $output as xs:string+) {
    <sequence>
    {
        for $model in $seq/(tei:model|tei:modelSequence|tei:modelGrp)[not(@output)] |
            $seq/(tei:model|tei:modelSequence|tei:modelGrp)[@output = $output][1]
        return
            <item>
            {
                if ($model/@predicate) then
                    <if test="{$model/@predicate}">
                        <then>{pm:model-or-sequence($ident, $model, $modules, $output)}</then>
                        <else>()</else>
                    </if>
                else
                    pm:model-or-sequence($ident, $model, $modules, $output)
            }
            </item>
    }
    </sequence>
};

declare %private function pm:get-class($ident as xs:string, $model as element(tei:model)) as xs:string+ {
    let $spec := $model/ancestor::tei:elementSpec[1]
    let $count := count($spec//tei:model)
    let $genClass := "tei-" || $ident || (if ($count > 1) then count($spec//tei:model[. << $model]) + 1 else ())
    return
        if ($model/tei:cssClass) then
            ('"' || $genClass ||'"', "(" || $model/tei:cssClass || ")")
        else if ($model/@cssClass) then
            ('"' || $genClass ||'"', (for $class in tokenize($model/@cssClass, "\s+") return '"' || $class || '"'))
        else
            '"' || $genClass ||'"'
};

declare %private function pm:lookup($modules as array(*), $task as xs:string, $arity as xs:int) as map(*)? {
    if (array:size($modules) > 0) then
        let $module := $modules?(array:size($modules))
        let $moduleDesc := $module?description
        let $name := $moduleDesc/@prefix || ":" || $task
        let $fn := $moduleDesc/function[@name = $name]
        return
            if (exists($fn)) then
                map { "function": $fn, "prefix": $module?prefix }
            else
                pm:lookup(array:subarray($modules, 1, array:size($modules) - 1), $task, $arity)
    else
        ()
};

declare %private function pm:expand-template($model as element(tei:model), $params as element(tei:param)*) {
    if ($model/pb:template) then (
        <let var="params">
            <expr>
                <map>
                {
                    for $param in $params
                    return
                        <entry key='"{$param/@name}"' value="{$param/@value}"/>
                }
                </map>
            </expr>
        </let>,
        <let var="content">
            <expr>
                <function-call name="model:template{count($model/preceding::pb:template) + 1}">
                    <param>$config</param>
                    <param>.</param>
                    <param>$params</param>
                </function-call>
            </expr>
            <return/>
        </let>
    ) else
        ()
};


declare function pm:map-parameters($signature as element(function), $params as element(tei:param)+,  $ident as xs:string, $modules as array(*),
    $output as xs:string+, $hasTemplate as xs:boolean?) {
    for $arg in subsequence($signature/argument, 4)
    let $mapped := $params[@name = $arg/@var]
    return
        if ($mapped) then
            let $nested := pm:get-model-elements($mapped, $output)
            return
                if ($nested) then
                    <param>{ pm:process-models($ident, $nested, $modules, $output) }</param>
                else if ($hasTemplate and $arg/@var = 'content') then
                    <param>$content</param>
                else
                    <param>{ ($mapped/@value/string(), $mapped/node(), "()")[1] }</param>
        else if ($arg/@cardinality = ("zero or one", "zero or more")) then
            <param>()</param>
        else if ($arg/@var = "optional") then
            ()
        else
            error($pm:NOT_FOUND, "No matching parameter found for argument " || $arg/@var)
};

(:~
 : Parameters in the ODD which do not match any declared parameter of the behaviour function are collected into
 : a map and passed to the behaviour function in a parameter $optional. For this the function must take $optional
 : as its last parameter. If not, the optional parameters are discarded.
 :)
declare %private function pm:optional-parameters($signature as element(function), $params as element(tei:param)+) {
    let $functionArgs := subsequence($signature/argument, 4)
    let $lastArg := $functionArgs[last()]
    return
        if ($lastArg/@var = "optional") then
            let $optional :=
                for $param in $params
                let $mapped := $functionArgs[@var = $param/@name]
                return
                    if ($mapped) then
                        ()
                    else
                        ``["`{$param/@name}`": `{$param/@value}`]``
            return
                <param>map {{{string-join($optional, ", ")}}}</param>
        else
            ()
};

declare %private function pm:get-model-elements($context as element(), $output as xs:string+) {
    $context/(
        tei:model[not(@output)]|tei:model[@output = $output] |
        tei:modelSequence[not(@output)]|tei:modelSequence[@output = $output] |
        tei:modelGrp[not(@output)]|tei:modelGrp[@output = $output]
    )
};

declare %private function pm:declare-template-functions($odd as element()) {
    for $tmpl at $count in $odd//pb:template
    return
        <function name="model:template{$count}">
            <param>$config as map(*)</param>
            <param>$node as node()*</param>
            <param>$params as map(*)</param>
            <body>{pm:template-body($tmpl)}</body>
        </function>
};

declare %private function pm:template-body($template as element(pb:template)) {
    let $children := $template/*
    return
        if ($children) then
            if (count($children) > 1) then
                '"Error: pb:template requires a single child element!"'
            else
                pm:template-body-element($children)
        else
            pm:template-body-string($template)
};

declare %private function pm:template-body-element($root as element()) {
    let $text := serialize($root, map { "indent": false() })
    let $code := replace($text, "\[\[(.*?)\]\]", "{\$config?apply-children(\$config, \$node, \$params?$1)}")
    return
        if (namespace-uri-from-QName(node-name($root)) = "") then
            '<t xmlns="">' || $code || '</t>/*'
        else
            $code
};

declare %private function pm:template-body-string($template as element(pb:template)) {
    "``[" || replace($template/string(), "\[\[(.*?)\]\]", "`{string-join(\$config?apply-children(\$config, \$node, \$params?$1))}`") || "]``"
};
