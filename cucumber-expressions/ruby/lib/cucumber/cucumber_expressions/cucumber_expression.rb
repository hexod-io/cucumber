# frozen_string_literal: true

require 'cucumber/cucumber_expressions/argument'
require 'cucumber/cucumber_expressions/tree_regexp'
require 'cucumber/cucumber_expressions/errors'

module Cucumber
  module CucumberExpressions
    # A compiled Cucumber Expression
    class CucumberExpression
      # Does not include (){} characters because they have special meaning
      ESCAPE_REGEXP = /([\\^\[$.|?*+\]])/.freeze
      PARAMETER_REGEXP = /(\\\\)?{([^}]*)}/.freeze
      OPTIONAL_REGEXP = /(\\\\)?\(([^)]+)\)/.freeze
      ALTERNATIVE_NON_WHITESPACE_TEXT_REGEXP = %r{([^\s^/]+)((/[^\s^/]+)+)}.freeze
      DOUBLE_ESCAPE = '\\\\'
      PARAMETER_TYPES_CANNOT_BE_ALTERNATIVE = 'Parameter types cannot be alternative: '
      PARAMETER_TYPES_CANNOT_BE_OPTIONAL = 'Parameter types cannot be optional: '

      attr_reader :source

      def initialize(expression, parameter_type_registry)
        @source = expression
        @parameter_types = []

        expression = process_escapes(expression)
        expression = process_optional(expression)
        expression = process_alternation(expression)
        expression = process_parameters(expression, parameter_type_registry)
        expression = "^#{expression}$"

        @tree_regexp = TreeRegexp.new(expression)
      end

      def match(text)
        Argument.build(@tree_regexp, text, @parameter_types)
      end

      def regexp
        @tree_regexp.regexp
      end

      def to_s
        @source.inspect
      end

      private

      def process_escapes(expression)
        expression.gsub(ESCAPE_REGEXP, '\\\\\1')
      end

      def process_optional(expression)
        # Create non-capturing, optional capture groups from parenthesis
        expression.gsub(OPTIONAL_REGEXP) do
          g2 = Regexp.last_match(2)
          # When using Parameter Types, the () characters are used to represent an optional
          # item such as (a ) which would be equivalent to (?:a )? in regex
          #
          # You cannot have optional Parameter Types i.e. ({int}) as this causes
          # problems during the conversion phase to regex. So we check for that here
          #
          # One exclusion to this rule is if you actually want the brackets i.e. you
          # want to capture (3) then we still permit this as an individual rule
          # See: https://github.com/cucumber/cucumber-ruby/issues/1337 for more info
          # look for double-escaped parentheses
          if Regexp.last_match(1) == DOUBLE_ESCAPE
            "\\(#{g2}\\)"
          else
            check_no_parameter_type(g2, PARAMETER_TYPES_CANNOT_BE_OPTIONAL)
            "(?:#{g2})?"
          end
        end
      end

      def process_alternation(expression)
        expression.gsub(ALTERNATIVE_NON_WHITESPACE_TEXT_REGEXP) do
          # replace \/ with /
          # replace / with |
          replacement = $&.tr('/', '|').gsub(/\\\|/, '/')
          if replacement.include?('|')
            replacement.split(/\|/).each do |part|
              check_no_parameter_type(part, PARAMETER_TYPES_CANNOT_BE_ALTERNATIVE)
            end
            "(?:#{replacement})"
          else
            replacement
          end
        end
      end

      def process_parameters(expression, parameter_type_registry)
        # Create non-capturing, optional capture groups from parenthesis
        expression.gsub(PARAMETER_REGEXP) do
          if Regexp.last_match(1) == DOUBLE_ESCAPE
            "\\{#{Regexp.last_match(2)}\\}"
          else
            type_name = Regexp.last_match(2)
            ParameterType.check_parameter_type_name(type_name)
            parameter_type = parameter_type_registry.lookup_by_type_name(type_name)
            raise UndefinedParameterTypeError, type_name if parameter_type.nil?

            @parameter_types.push(parameter_type)

            build_capture_regexp(parameter_type.regexps)
          end
        end
      end

      def build_capture_regexp(regexps)
        return "(#{regexps[0]})" if regexps.size == 1

        capture_groups = regexps.map { |group| "(?:#{group})" }
        "(#{capture_groups.join('|')})"
      end

      def check_no_parameter_type(string, message)
        raise CucumberExpressionError, "#{message}#{source}" if PARAMETER_REGEXP =~ string
      end
    end
  end
end
