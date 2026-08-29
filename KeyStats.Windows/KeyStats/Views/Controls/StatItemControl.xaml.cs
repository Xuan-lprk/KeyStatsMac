using System;
using System.Windows;
using System.Windows.Controls;

namespace KeyStats.Views.Controls;

public partial class StatItemControl : System.Windows.Controls.UserControl
{
    public static readonly DependencyProperty IconProperty =
        DependencyProperty.Register(nameof(Icon), typeof(string), typeof(StatItemControl),
            new PropertyMetadata("", OnIconChanged));

    public static readonly DependencyProperty TitleProperty =
        DependencyProperty.Register(nameof(Title), typeof(string), typeof(StatItemControl),
            new PropertyMetadata("", OnTitleChanged));

    public static readonly DependencyProperty ValueProperty =
        DependencyProperty.Register(nameof(Value), typeof(string), typeof(StatItemControl),
            new PropertyMetadata("0", OnValueChanged));

    public string Icon
    {
        get => (string)GetValue(IconProperty);
        set => SetValue(IconProperty, value);
    }

    public string Title
    {
        get => (string)GetValue(TitleProperty);
        set => SetValue(TitleProperty, value);
    }

    public string Value
    {
        get => (string)GetValue(ValueProperty);
        set => SetValue(ValueProperty, value);
    }

    public StatItemControl()
    {
        InitializeComponent();
        // Ensure initial values are rendered even when bindings resolve to defaults.
        IconText.Text = Icon ?? "";
        TitleText.Text = Title ?? "";
        ValueText.Text = NormalizeDisplayValue(Value);
    }

    private static void OnIconChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is StatItemControl control)
        {
            control.IconText.Text = e.NewValue as string ?? "";
        }
    }

    private static void OnTitleChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is StatItemControl control)
        {
            control.TitleText.Text = e.NewValue as string ?? "";
        }
    }

    private static void OnValueChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is StatItemControl control)
        {
            control.ValueText.Text = NormalizeDisplayValue(e.NewValue as string);
        }
    }

    private static string NormalizeDisplayValue(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ? "0" : value ?? "0";
    }
}
