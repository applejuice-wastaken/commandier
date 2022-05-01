local command_tree;
local Node;
do
    local nativeSetPrefix = chat.setFiguraCommandPrefix
    local setPrefix = 0;
    local registered_nodes;

    function chat.setFiguraCommandPrefix(str)
        nativeSetPrefix(str)
        setPrefix = str
    end

    local function argWrap(required, str)
        if required then
            return "<" .. str .. ">";
        else

            return "[" .. str .. "]";
        end
    end

    local function copyTable(t)
        local ret = {}
        for k, v in pairs(t) do
            ret[k] = v
        end
        return ret
    end

    local function travel(registered_nodes, chunks, idx, args, executor, takenPath)
        if idx <= #chunks then
            for _, node in pairs(registered_nodes) do
                local argsCopy = copyTable(args)

                if node.getProcessor()(chunks[idx], argsCopy) then
                    local takenPathCopy = copyTable(takenPath)
                    table.insert(takenPathCopy, node);
                    return travel(node.getNextNodes(), chunks, idx + 1, argsCopy, node.getExecutor(), takenPathCopy)
                end
            end

            if #registered_nodes == 0 then
                print("Too many arguments")
                return
            end
        end

        return executor(args, takenPath);
    end

    local function getAllFormats(node, memo, required, forcedPath)
        local rets = {}

        local children;

        if #forcedPath > 0 then
            children = { forcedPath[1] }
        else
            children = node.getNextNodes()
        end

        for _, child in pairs(children) do
            local childRets;

            if memo[child] then
                childRets = { argWrap(node.isDefaultExecutor(), "...") };
            else
                local memoCopy = copyTable(memo)
                memoCopy[child] = true

                local forcedPathCopy;

                if #forcedPath > 0 then
                    forcedPathCopy = copyTable(forcedPath);
                    table.remove(forcedPathCopy, 1);
                else
                    forcedPathCopy = forcedPath;
                end

                childRets = getAllFormats(child, memoCopy, node.isDefaultExecutor(), forcedPathCopy);
            end


            for _, childRet in pairs(childRets) do
                local transform = {};
                local shouldWrap = false;
                if not required and child.isDefaultExecutor() then
                    table.insert(transform, node.asArgument(false));
                elseif required then
                    table.insert(transform, node.asArgument(true));
                else
                    table.insert(transform, "[" .. node.asArgument(true));
                    shouldWrap = true;
                end

                for _, chunk in pairs(childRet) do
                    table.insert(transform, chunk);
                end

                if shouldWrap then
                    transform[#transform] = transform[#transform] .. "]";
                end


                table.insert(rets, transform);
            end
        end

        if not node.isDefaultExecutor() and #node.getNextNodes() == 0 then
            table.insert(rets, { node.asArgument(required) });
        end

        return rets;
    end

    function onCommand(cmd)
        cmd = string.sub(cmd, string.len(setPrefix) + 1);

        local chunks = {};

        for chunk in string.gmatch(cmd, "[^ ]+") do
            table.insert(chunks, chunk);
        end

        travel(registered_nodes, chunks, 1, {}, function()
            print("Unknown command \"" .. chunks[1] .. "\", type " .. setPrefix .. "help for help")
        end, {})
    end

    function Node(processor, consumeRest, asArgument)
        local this = {};

        local nodes = {};

        local executor = function(args, path)
            print("Incomplete command")
            local first = table.remove(path, 1);
            for _, format in pairs(getAllFormats(first, {}, true, path)) do
                print("    " .. table.concat(format, " "))
            end
        end;

        local defaultExecutor = true;

        function this.executes(func)
            executor = func;
            defaultExecutor = false;
            return this;
        end

        function this.append(node)
            table.insert(nodes, node);
            return this;
        end

        function this.getNextNodes()
            return nodes;
        end

        function this.getExecutor()
            return executor;
        end

        function this.isDefaultExecutor()
            return defaultExecutor;
        end

        function this.consumesRest()
            return consumeRest;
        end

        function this.getProcessor()
            return processor;
        end

        function this.asArgument(required)
            return asArgument(required);
        end

        return this;
    end

    registered_nodes = {};
    command_tree = {
        register = function(node)
            table.insert(registered_nodes, node);
        end
    }

    function literal(str)
        return Node(function(value)
            return value == str
        end, false, function(isRequired)
            if isRequired then
                return str;
            end

            return argWrap(false, str)
        end)
    end

    function integer(arg)
        return Node(function(value, accumulated)
            local value = tonumber(value)
            if value ~= nil then
                accumulated[arg] = value;
                return true;
            end
            return false;
        end, false, function(isRequired)
            return argWrap(isRequired, arg .. ": integer")
        end)
    end

    function str(arg, rest)
        return Node(function(value, accumulated)
            accumulated[arg] = value;
            return true;
        end, rest, function(isRequired)
            if rest then
                return argWrap(isRequired, arg .. "...: string")
            end

            return argWrap(isRequired, arg .. ": string")
        end)
    end

    command_tree.register(
        literal("help")
        .append(
            str("name")
            .executes(function(args)
                local matched = false;
                for _, node in pairs(registered_nodes) do
                    if node.getProcessor()(args.name, {}) then
                        print("All formats for command " .. node.asArgument(true) .. ":")
                        for _, format in pairs(getAllFormats(node, {}, true, {})) do
                            print("    " .. table.concat(format, " "))
                        end
                        matched = true;
                    end
                end
                if not matched then
                    print("No command matching " .. args.name)
                end
            end
            )
        )
        .executes(function()
            print("All commands:")
            for _, node in pairs(registered_nodes) do
                print("    " .. node.asArgument(true))
            end
        end)
    )
end






-- example
if true then
    chat.setFiguraCommandPrefix(">")
    command_tree.register(
        literal("hello")
        .append(
            str("person")
            .append(
                str("person2")
                .append(
                    str("person3")
                    .executes(
                        function(args)
                            print("Hello " .. args.person .. " and " .. args.person2 .. " and " .. args.person3 .. "!")
                        end
                    )
                )
            )
            .executes(
                function(args)
                    print("Hello " .. args.person .. "!")
                end
            )
        )
        .executes(
            function()
                print("Hello?")
            end
        )
    )


    command_tree.register(
        literal("eat")
        .append(
            integer("much").append(str("what").executes(
                function(args)
                    print("You ate " .. args.much .. " " .. args.what .. "???")
                end
            )
            )
        )
    )
end