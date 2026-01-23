{{--
LAPORTE Theme Override: Custom Head Content

This overrides the default BookStack template to REMOVE the exclusion
of custom head content from settings/admin pages.

Original excludes: request()->routeIs('settings.category')
This override: Allows custom head on ALL pages including settings
--}}
@inject('headContent', 'BookStack\Theming\CustomHtmlHeadContentProvider')

@if(setting('app-custom-head'))
    {!! $headContent->forWeb() !!}
@endif
