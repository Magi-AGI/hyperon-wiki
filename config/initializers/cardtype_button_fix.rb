
Rails.application.config.after_initialize do
  Card::Set::Type::Cardtype::HtmlFormat.class_eval do
    def configure_link css_class=nil
      return "" unless Card.fetch(card, :type, :structure, new: {}).ok?(:update)
      title_text = t(:format_configure_card, cardname: safe_name.pluralize)
      link_to_card card, title_text,
                   path: { view: :board,
                           board: { tab: :rules_tab },
                           set: Card::Name[safe_name, :type] },
                   class: css_classes("configure-type-link ms-3", css_class)
    end

    def add_link opts={}
      title_text = t(:format_add_card, cardname: safe_name)
      link_to title_text, add_link_opts(opts)
    end
  end

  # Clear view cache so cached add_button views are regenerated
  Card::Cache.reset_all rescue nil
end
