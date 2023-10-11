module Settings
  module Imports
    class ShowView < ApplicationView
      def initialize(import:)
        @import = import
      end

      def template
        render Settings::H1Component.new do
          "Import Status"
        end
        p class: "mb-8 -mt-6 text-500" do
          @import.created_at.to_formatted_s(:date)
        end
        div data: @import.complete? ? {} : {content_src: helpers.settings_import_path(@import)} do
          render Settings::Imports::StatusComponent.new import: @import
        end
      end
    end
  end
end
