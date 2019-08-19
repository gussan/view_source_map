module ViewSourceMap
  class Railtie < Rails::Railtie
    initializer "render_with_path_comment.initialize" do
      if !ENV["DISABLE_VIEW_SOURCE_MAP"] && Rails.env.development?
        ViewSourceMap.attach
      end
    end
  end

  def self.attach
    return if defined?(@attached) && @attached
    @attached = true
    ActionView::PartialRenderer.class_eval do
      def render_with_path_comment(context, options, block)
        content = render_without_path_comment(context, options, block)
        return content if ViewSourceMap.force_disabled?(options)
        return content unless content.respond_to?(:template)

        if content.format == :html
          if options[:layout]
            name = "#{options[:layout]}(layout)"
          else

            return content unless content.template.respond_to?(:identifier)
            path = Pathname.new(content.template.identifier)
            name = path.relative_path_from(Rails.root)
          end

          build_rendered_template("<!-- BEGIN #{name} -->\n#{content.body}<!-- END #{name} -->".html_safe, content.template)
        else
          content
        end
      end
      alias_method :render_without_path_comment, :render
      alias_method :render, :render_with_path_comment
    end

    ActionView::TemplateRenderer.class_eval do
      def render_template_with_path_comment(view, template, layout_name = nil, locals = {})
        locals ||= {}

        render_with_layout(view, template, layout_name, locals) do |layout|
          instrument(:template, identifier: template.identifier, layout: (layout && layout.virtual_path)) do
            content = template.render(view, locals) { |*name| view._layout_for(*name) }
            return content if ViewSourceMap.force_disabled?(locals)

            path = Pathname.new(template.identifier)

            if template.format == :html && path.file?
              name = path.relative_path_from(Rails.root)
              "<!-- BEGIN #{name} -->\n#{content}<!-- END #{name} -->".html_safe
            else
              content
            end
          end
        end
      end
      alias_method :render_template_without_path_comment, :render_template
      alias_method :render_template, :render_template_with_path_comment
    end
  end

  def self.detach
    return unless @attached
    @attached = false
    ActionView::PartialRenderer.class_eval do
      undef_method :render_with_path_comment
      alias_method :render, :render_without_path_comment
    end

    ActionView::TemplateRenderer.class_eval do
      undef_method :render_template_with_path_comment
      alias_method :render_template, :render_template_without_path_comment
    end
  end

  def self.force_disabled?(options)
    return false if options.nil?
    return true  if options[:view_source_map] == false
    return false if options[:locals].nil?
    options[:locals][:view_source_map] == false
  end
end
